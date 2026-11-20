set_project("SDLGamepadProbe")
set_languages("c11")
set_toolchains("clang")
set_warnings("error")
-- The probe runs on every macOS the app supports, so it shares the app's floor.
add_mxflags("-mmacosx-version-min=13.0")
add_ldflags("-mmacosx-version-min=13.0")

target("SDLGamepadProbe")
  set_kind("binary")
  add_files("*.m")
  add_frameworks("Foundation", "GameController")
  on_load(function (target)
    import("lib.detect.find_package")
    local sdl = assert(find_package("pkgconfig::sdl3"), "SDL3 not found by pkg-config")
    -- xmake's compile_commands generator rewrites -isystem to -I, which makes
    -- clang-tidy lint the SDL headers. -idirafter keeps them system headers.
    for _, dir in ipairs(sdl.includedirs or sdl.sysincludedirs or {}) do
      target:add("mxflags", "-idirafter", dir, {force = true})
    end
    target:add("linkdirs", sdl.linkdirs)
    target:add("links", sdl.links)
    target:add("ldflags", sdl.ldflags)
  end)
