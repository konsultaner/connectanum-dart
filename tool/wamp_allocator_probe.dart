// Diagnostic-only wrapper support. Never imported by production packages.
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

/// A separate smoke process checks counters against a known native allocation.
void main() {
  if (!Platform.isLinux) throw UnsupportedError('Linux/glibc smoke only');
  final probe = _AllocatorProbe();
  final before = probe.capture();
  const requested = 64 * 1024 * 1024;
  final allocation = probe.calloc(1, requested);
  if (allocation == nullptr) throw StateError('Smoke allocation failed');
  late final Map<String, Object> allocated;
  try {
    allocated = probe.capture();
  } finally {
    probe.free(allocation);
  }
  stdout.writeln(
    jsonEncode({
      'requested_bytes': requested,
      'before': before,
      'allocated': allocated,
      'after_free': probe.capture(),
    }),
  );
}

/// Read glibc's all-arena counters without changing allocator policy or GC.
///
/// Counters are not RSS or exact live bytes: thread caches are not free bins.
/// open_memstream itself allocates a small temporary buffer. This extension
/// perturbs execution and its enclosing run cannot provide parity acceptance.
void registerAllocatorProbe() {
  if (!Platform.isLinux) {
    throw UnsupportedError('Allocator attribution requires Linux/glibc');
  }
  final probe = _AllocatorProbe();
  registerExtension('ext.connectanum.diagnosticMallocInfo', (_, _) async {
    try {
      return ServiceExtensionResponse.result(jsonEncode(probe.capture()));
    } catch (_) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Allocator diagnostic failed',
      );
    }
  });
}

final class _AllocatorProbe {
  final library = DynamicLibrary.process();
  late final calloc = library
      .lookupFunction<
        Pointer<Void> Function(Size, Size),
        Pointer<Void> Function(int, int)
      >('calloc');
  late final free = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  late final open = library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Pointer<Uint8>>, Pointer<UintPtr>),
        Pointer<Void> Function(Pointer<Pointer<Uint8>>, Pointer<UintPtr>)
      >('open_memstream');
  late final info = library
      .lookupFunction<
        Int Function(Int, Pointer<Void>),
        int Function(int, Pointer<Void>)
      >('malloc_info');
  late final close = library
      .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'fclose',
      );
  late final version = library
      .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
        'gnu_get_libc_version',
      );

  Map<String, Object> capture() {
    // Resolve before allocating so a missing glibc symbol cannot leak slots.
    final allocate = calloc, release = free, openStream = open;
    final readInfo = info, closeStream = close, getVersion = version;
    final words = allocate(2, sizeOf<UintPtr>());
    if (words == nullptr) throw StateError('Allocator probe allocation failed');
    final buffer = words.cast<Pointer<Uint8>>();
    final length = words.cast<UintPtr>() + 1;
    var stream = nullptr.cast<Void>();
    try {
      stream = openStream(buffer, length);
      if (stream == nullptr) throw StateError('Allocator stream failed');
      final status = readInfo(0, stream);
      final closing = stream;
      stream = nullptr;
      final closeStatus = closeStream(closing);
      if (status != 0 ||
          closeStatus != 0 ||
          buffer.value == nullptr ||
          length.value == 0 ||
          length.value > 524288) {
        throw StateError('Allocator counters unavailable or oversized');
      }
      final xml = utf8.decode(buffer.value.asTypedList(length.value));
      final versionPointer = getVersion();
      if (versionPointer == nullptr) throw StateError('Missing glibc version');
      final versionBytes = <int>[];
      for (var index = 0; index < 64; index++) {
        final byte = versionPointer[index];
        if (byte == 0) break;
        versionBytes.add(byte);
      }
      if (versionBytes.isEmpty || versionBytes.length == 64) {
        throw StateError('Invalid glibc version');
      }
      return {
        'type': 'ConnectanumAllocatorDiagnostic',
        'pid': pid,
        'glibc_version': ascii.decode(versionBytes),
        'malloc_info_xml': xml,
      };
    } finally {
      if (stream != nullptr) closeStream(stream);
      release(buffer.value.cast<Void>());
      release(words);
    }
  }
}
