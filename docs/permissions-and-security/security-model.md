# Security model

OpenJoystickDriver works with System Integrity Protection (SIP) and Apple Mobile File Integrity (AMFI) turned on.

> [!WARNING]
> Never turn off SIP or AMFI for OJD. No OJD feature needs it. If a guide says to do so, do not follow it.

## Signing

Apple notarized the release app, and the maintainer signed it. Tester builds use a Developer ID signature and are also notarized.

## System extension

The optional Xbox USB driver extension is a DriverKit system extension. It runs in user space, not in the kernel. macOS asks for your approval before it starts. OJD uses it only for Xbox One and Xbox Series controllers on USB. For more information, see [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md).

## Data on your Mac

OJD stores this data locally:

- Profiles in `~/Library/Application Support/OpenJoystickDriver/`. Only your user can read the folder.
- Logs in `~/Library/Logs/OpenJoystickDriver/`. Each start of OJD clears them.
- Settings in the `com.openjoystickdriver` preferences domain.

The only network request in the OJD source is the update check. It runs when you click **Check Now** and contacts GitHub. OJD does not send controller data. OJD has no automatic update.

## Support report

**Copy Support Report** copies a JSON report to the clipboard. OJD does not save it to disk. The report contains service status, virtual device details, Input Monitoring state, build identity, and Apple game controller data. It contains product names of your devices. By its own privacy flags, it leaves out serial numbers, file paths, packet data, and HID location IDs. Read the report before you share it.

## Further reading

- [Permissions](permissions.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
- [Uninstalling OpenJoystickDriver](../updating-and-uninstalling/uninstalling-openjoystickdriver.md)
