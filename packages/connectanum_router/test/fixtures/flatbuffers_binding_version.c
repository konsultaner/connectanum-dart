/* Minimal ABI probe: no message owner can be exported by this library. */
#ifdef FLATBUFFERS_BINDING_VERSION
unsigned int ct_flatbuffers_binding_version(void) {
    return FLATBUFFERS_BINDING_VERSION;
}
#else
int ct_flatbuffers_fixture_anchor(void) { return 0; }
#endif
