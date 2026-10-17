// VM bulk copies use backing-buffer identity. Browser read-only buffer
// wrappers do not expose that identity; retain the SDK implementation there.
export 'byte_vector_builder_sdk.dart'
    if (dart.library.ffi) 'byte_vector_builder_vm.dart';
