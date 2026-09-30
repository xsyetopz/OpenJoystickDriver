# Clone and fake controllers

This article explains why copies of well-known controllers behave differently and how OpenJoystickDriver (OJD) treats them.

Some controllers look like a Sony or Microsoft controller but use a different chip and a different identity. OJD identifies a controller by its VID:PID, not by its shape or its name on the box. A clone with a different VID:PID is a different device to OJD. For more information, see [Finding your controller ID](finding-your-controller-id.md).

Clones often send data in a different format, so the driver for the original controller may read them wrongly. Do not report a clone under the name of the original controller.

## Known clones

| Controller | Copies | Notes |
| --- | --- | --- |
| Zhongqing ZQDZ-P3-BT-3D-FZ-V2.0 | PS3 controller | The maintainer owns this fake. The chip is not identified. |
| Ant Esports GP100 | PS3 controller | A Shanwan PS3 clone. VID:PID `2563:0575` in PS3/PC mode. |

The Ant Esports GP100 starts in XInput mode. In that mode macOS sees no input. To switch it to PS3/PC mode, hold **Select** and **B** while you connect it. One tester reports **Start** and **B** instead. For more information, see [the Shanwan test record](../../contributing/testing/ps3-third-party.md).

## What the warning sign means

A controller in the Unverified tier has a record in the OJD catalog, but nobody tested it on real hardware. The warning does not say that the controller is fake. It says that OJD may work, may partly work, or may not work with it. For more information, see [Supported controllers](supported-controllers.md).

## Further reading

- [Connection types](connection-types.md)
- [Reporting a bug](../troubleshooting/reporting-a-bug.md)
