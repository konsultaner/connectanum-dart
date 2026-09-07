# local_auth_windows 2.0.2 requires legacy /await semantics (a plain return
# inside a coroutine). Keep that ABI until upstream adopts standard coroutines.
# Current MSVC requires this opt-in; never apply it to unrelated targets.
if(MSVC AND TARGET local_auth_windows_plugin)
  get_target_property(local_auth_options local_auth_windows_plugin COMPILE_OPTIONS)
  if("/await" IN_LIST local_auth_options)
    get_target_property(local_auth_definitions local_auth_windows_plugin
      COMPILE_DEFINITIONS)
    if(NOT "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS"
        IN_LIST local_auth_definitions)
      set_property(TARGET local_auth_windows_plugin APPEND PROPERTY
        COMPILE_DEFINITIONS _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
    endif()
    unset(local_auth_definitions)
  endif()
  unset(local_auth_options)
endif()
