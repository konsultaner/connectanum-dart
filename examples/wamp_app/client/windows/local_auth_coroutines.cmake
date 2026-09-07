# local_auth_windows already requires C++20, but 2.0.2 also adds the obsolete
# /await flag. Use standard coroutines instead of suppressing MSVC STL1011.
# https://learn.microsoft.com/en-us/cpp/build/reference/await-enable-coroutine-support
if(TARGET local_auth_windows_plugin)
  get_target_property(local_auth_options local_auth_windows_plugin COMPILE_OPTIONS)
  if(local_auth_options)
    list(REMOVE_ITEM local_auth_options "/await")
    set_property(TARGET local_auth_windows_plugin PROPERTY
      COMPILE_OPTIONS "${local_auth_options}")
  endif()
  unset(local_auth_options)
endif()
