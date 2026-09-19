import 'dart:ffi' as ffi;

import 'package:connectanum_client/src/transport/native/runtime.dart';

String? nativeClientRuntimeSkipReason() {
  final resolvedPath = NativeLibraryLoader.resolvePath();
  try {
    ffi.DynamicLibrary.open(resolvedPath);
    return null;
  } catch (error) {
    return 'Native client runtime unavailable: $error';
  }
}
