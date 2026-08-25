import 'attachment_chunk_cache_base.dart';
import 'attachment_chunk_cache_factory_stub.dart'
    if (dart.library.io) 'attachment_chunk_cache_factory_io.dart'
    if (dart.library.js_interop) 'attachment_chunk_cache_factory_web.dart';

export 'attachment_chunk_cache_base.dart';

AttachmentChunkCache createAttachmentChunkCache() =>
    createPlatformAttachmentChunkCache();
