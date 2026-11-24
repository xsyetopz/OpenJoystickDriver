set_project("SDL2GamepadProbe")
set_languages("c17")
set_toolchains("clang")
set_warnings("error")
-- CrossOver ships its SDL 2 for x86_64 only, and the probe loads it into its own process. The
-- clang toolchain passes no -arch for set_arch, so the flag is explicit. The probe runs on every
-- macOS the app supports, so it shares the app's floor.
add_cflags("-arch", "x86_64", "-mmacosx-version-min=13.0", {force = true})
add_ldflags("-arch", "x86_64", "-mmacosx-version-min=13.0", {force = true})

target("SDL2GamepadProbe")
  set_kind("binary")
  add_files("main.c")
