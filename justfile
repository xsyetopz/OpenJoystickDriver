release-local-install version="0.5.0-alpha.5":
    OJD_ENV=release OJD_INSTALL_AFTER_PACKAGE=1 ./scripts/ojd package release "{{version}}"
