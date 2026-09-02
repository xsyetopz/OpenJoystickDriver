# OpenJoystickDriver GitHub Issues and Pull Requests

Snapshot of every issue and pull request returned by the GitHub CLI for [xsyetopz/OpenJoystickDriver](https://github.com/xsyetopz/OpenJoystickDriver). GitHub remains the source of truth. Expiring authentication query parameters are stripped from quoted links.

Refresh from the repository root:

```bash
./scripts/ojd docs export-external-issues
```

## Issues

| Issue | State | Title |
| --- | --- | --- |
| [#8](issue-8.md) | OPEN | Steam Controller Support |
| [#9](issue-9.md) | OPEN | Xbox 360 wireless not work |
| [#10](issue-10.md) | CLOSED | xbox 360 wired controller lighted logo ring continuous flashing |
| [#11](issue-11.md) | OPEN | Logitech F310 (Xinput mode) button mapping wrong |
| [#12](issue-12.md) | CLOSED | Readme instructions should explain how to uninstall the special daemon/drivers. |
| [#14](issue-14.md) | OPEN | Device support request: Razer Wolverine V3 Tournament Edition (1532:0A43) |
| [#15](issue-15.md) | CLOSED | Logitech F310 (X mode): no input on macOS 26 — profile declares wrong OUT endpoint (1 → hardware uses 2) |
| [#18](issue-18.md) | OPEN | Original Xbox One controller (model 1537, 045E:02D1) falls back to genericHID — request GIP profile |
| [#19](issue-19.md) | OPEN | Add controller record: Razer Wolverine V2 (1532:0a29) |
| [#21](issue-21.md) | OPEN | Nacon Revolution X Pro (3285:0634): add GIP profile and investigate USB disconnects |
| [#22](issue-22.md) | OPEN | Controller with bDeviceClass=0 is never discovered (vendor-specific class only on interface) |
| [#23](issue-23.md) | OPEN | 0.5.0-alpha.4 leaks around 103 MB/h while idle. Fixed on main, please cut a release |

## Pull requests

| Pull request | State | Title |
| --- | --- | --- |
| [#1](pull-1.md) | MERGED | Add Flydigi Vader 5S support with per-device endpoint config |
| [#3](pull-3.md) | CLOSED | feat: Xbox 360 wired parser, GIP LED control, profile, schema, tests |
| [#4](pull-4.md) | MERGED | chore(deps): bump softprops/action-gh-release from 2 to 3 |
| [#6](pull-6.md) | MERGED | Prepare 0.2.0 release packaging |
| [#13](pull-13.md) | MERGED | build(deps): bump actions/checkout from 6 to 7 |
| [#16](pull-16.md) | MERGED | Fix Logitech F310 OUT endpoint (1 -> 2) |
| [#20](pull-20.md) | MERGED | fix(controllers): send GIP rumble frames without the internal option flag |
| [#24](pull-24.md) | OPEN | Fix Xbox 360 wired button bits and Rock Candy endpoints |
| [#26](pull-26.md) | OPEN | fix(driverkit): emit a kext-legal CFBundleVersion for the dext |
| [#27](pull-27.md) | OPEN | Add verified PDP Xbox 360 controller 0e6f:0401 support |
