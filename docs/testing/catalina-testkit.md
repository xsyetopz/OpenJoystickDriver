# Catalina foreground test kit

macOS 10.15 can run the foreground app and headless CLI. Login-item registration through `SMAppService.mainApp` requires macOS 13 or later, so Catalina testing must not install a LaunchAgent fallback.

Copy the signed universal app to the Catalina machine and run:

```bash
./scripts/ojd diagnose catalina /Applications/OpenJoystickDriver.app
```

The check verifies:

- `LSMinimumSystemVersion` and the executable deployment target are 10.15;
- the application contains an x86_64 slice;
- the icon and main executable exist;
- no LaunchAgent or helper daemon is packaged;
- the headless CLI starts.

For functional testing, open the app directly, grant the requested privacy permissions to `OpenJoystickDriver.app`, connect a controller, and run the input test. Automatic launch at login is not supported on Catalina.
