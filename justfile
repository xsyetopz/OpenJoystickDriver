release-local-install version="0.5.0-alpha.3":
    OJD_ENV=release ./scripts/ojd package release "{{version}}"
    rm -rf /Applications/OpenJoystickDriver.app
    cp -R .build/debug/OpenJoystickDriver.app /Applications/
