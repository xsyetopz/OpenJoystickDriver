# Catalina Foreground Test Kit

macOS 10.15 can run the foreground app and headless CLI. Login-item registration through `SMAppService.mainApp` requires macOS 13 or later, so Catalina testing must not install a LaunchAgent fallback.

Copy the signed universal app to Catalina, then run:

```bash
./Scripts/ojd diagnose catalina /Applications/OpenJoystickDriver.app
```

The check needs `python3`, `otool` and `lipo`, which Catalina provides only with the Command Line Tools (`xcode-select --install`). It verifies:

- `LSMinimumSystemVersion` and the executable deployment target are 10.15;
- the application contains an x86_64 slice;
- the icon, main executable and bundled Swift Concurrency runtime exist;
- no LaunchAgent or helper daemon is packaged;
- the headless CLI starts.

For functional testing, open the app directly and grant the requested privacy permissions to `OpenJoystickDriver.app`. Connect a controller, then enable Live in that controller's Settings.

If the window is unavailable, use:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller state
```

Automatic launch at login is not supported on Catalina.
