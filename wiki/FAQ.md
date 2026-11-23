# Frequently Asked Questions

Short answers about OpenJoystickDriver (OJD), with links to details.

```mermaid
flowchart LR
    q[Question] --> a[Short answer] --> p[Full page]
```

## Contents

- [About OpenJoystickDriver](#about-openjoystickdriver)
- [Setting Up](#setting-up)
- [Controllers](#controllers)
- [Games and Apps](#games-and-apps)
- [Your Data and Updates](#your-data-and-updates)
- [Getting Help](#getting-help)
- [Further Reading](#further-reading)

## About OpenJoystickDriver

### What Does OpenJoystickDriver Do?

It makes controllers your Mac doesn't support work with Mac games, as a [virtual gamepad](Glossary.md#terms). It can also turn buttons into keys and clicks ([Getting Started](Getting-Started.md)).

### Is It Free?

Yes. Open source (Mozilla Public License 2.0) on [GitHub](https://github.com/xsyetopz/OpenJoystickDriver).

### Which Macs Does It Run On?

Apple silicon or Intel, macOS 13 (Ventura) or later.

### Is It Finished?

No. It's alpha software: [Known Issues](Known-Issues.md).

## Setting Up

### Where Is the App After I Open It?

In the menu bar. Click the controller icon, then **Open OpenJoystickDriver** ([Find the Menu-Bar Icon](Getting-Started.md#find-the-menu-bar-icon)).

![Menu-bar icon with a red arrow](../docs/screenshots/steps/menu-bar-icon.png)

### Why Input Monitoring and Accessibility?

**Input Monitoring** reads your controller. **Accessibility** runs the virtual gamepad and sends keys and pointer moves ([Permissions](Permissions-and-Security.md#permissions)).

### How Do I Allow the Permissions?

In **System Settings** > **Privacy & Security**, turn on **OpenJoystickDriver** under **Input Monitoring** and **Accessibility** (**Device Control and Data Access** on macOS 27). [Pictures](Permissions-and-Security.md#grant-input-monitoring-and-accessibility). Not in the list? Click **+**, choose it in **Applications**, turn it on ([details](Permissions-and-Security.md#if-openjoystickdriver-isnt-in-the-list)).

### Are the Permissions On?

Click **Access**. Each says **Allowed**.

![Access area with arrows at Access and Allowed](../docs/screenshots/steps/access-permissions.png)

### Do I Turn Off SIP or AMFI?

No. They are macOS safety locks. Keep both on.

### Does OJD Start When I Log In?

On macOS 13 or later. Turn off **Open at login** in **Settings** to stop it ([Allow the Login Item](Getting-Started.md#allow-the-login-item)).

### Do I Need the Xbox USB Driver?

Only for an Xbox One or Series controller on USB. Approve the [Xbox USB driver](Glossary.md#terms) once. In **System Settings** > **General** > **Login Items & Extensions**, scroll to **Extensions**, click **By Category**, click the **(i)** beside **Driver Extensions**, turn on **OpenJoystickDriver**, and click **Done**. On macOS 13 and 14, click **Allow** in **System Settings** > **Privacy & Security**. [Pictures](Connecting-Controllers.md#approve-the-driver).

### Do I Need Xcode?

Only to build from source with the Xbox USB driver and Shortcuts actions ([Building From Source](Building-from-Source.md)).

## Controllers

### Will My Controller Work?

Check [Supported Controllers](Supported-Controllers.md), or connect it and look in the menu.

### How Do I Connect over Bluetooth?

Pair it in **System Settings** > **Bluetooth**: point at it under **Nearby Devices** and click **Connect** ([picture](Connecting-Controllers.md#connect-over-bluetooth)).

### How Do I Test My Controller?

Select it in **Controllers** and click **Open Input Test**. **Working** means games can use it ([Testing a Controller](Testing-a-Controller.md)).

![Controllers area with arrows at Working and Open Input Test](../docs/screenshots/steps/controller-working.png)

### Can I Use Several Controllers at Once?

Yes. Each gets its own virtual gamepad ([details](Playing-Games.md#how-games-see-your-controller)).

### Why Does My Controller Say Handled by macOS?

macOS supports it, so OJD shows no virtual gamepad. Some controllers have a **Handled by** menu ([Controllers Area](Using-the-App.md#controllers-area)).

### Why Does My Clone Act Differently?

A clone may send different data, so OJD may work with it fully, partly, or not at all: [Clone and Fake Controllers](Supported-Controllers.md#clone-and-fake-controllers).

### Can I Add an Unsupported Controller?

Yes, with a mod: a folder that adds or changes a [controller record](Controller-Records.md). The app can't edit records. See [Add Support for a Controller](Start-Add-Support-for-a-Controller.md) or [Writing Controller Mods](Writing-Controller-Mods.md).

## Games and Apps

### Why Does It Work in One App Only?

Apps listen for different gamepad kinds. Steam reads the default Xbox-style one. Safari and some Mac games read another ([Game Does Not See the Controller](Troubleshooting.md#game-does-not-see-the-controller)).

### What Is the Gamepad Kind?

The [kind](Glossary.md#terms) is the controller games think you have. Keep **Automatic** unless a game sees nothing.

| Pick | For |
| --- | --- |
| **For Steam and SDL games** | Steam, emulators, SDL games (SDL is a controller toolkit) |
| **For Apple Game Controller games** | Safari and Mac games with Apple's controller support |

See [the kind setting](Using-the-App.md#virtual-gamepad-kind).

### Does OJD Work with Steam?

Yes, with the default [kind](Glossary.md#terms). The maintainer saw every control and rumble work on macOS 27 ([details](Playing-Games.md#game-and-app-compatibility)).

Steam and OJD can't both read a USB pad: whichever starts first holds it. Start OJD first and it keeps the pad while Steam runs. Start Steam first and `ojd status` lists the pad under unsupported devices as `device-in-use`, **Used by** `steam_osx`; OJD serves it again as soon as Steam quits. The maintainer saw both orders with a Razer Wolverine Tournament Edition and an 8BitDo Ultimate 2C on macOS 27. Whether turning off Steam Input stops Steam from taking the pad is untested. ([details](Known-Issues.md#another-app-reads-a-usb-controller-directly))

To give one game its own SDL options, set a [launch setting](Playing-Games.md#launch-settings-per-app) and put `ojd virtual launch -- %command%` \1 Starting a game from Steam this way is untested.

### Does Rumble Work in Games?

It should, with motors and the default gamepad, but it's untested on real hardware. Game lighting doesn't reach the controller ([details](Playing-Games.md#rumble-and-lighting)).

### Can It Act as a Mouse or Keyboard?

Yes, with a [profile](Glossary.md#terms): [Control the Mac with a Controller](Start-Control-the-Mac.md).

## Your Data and Updates

### Does OJD Use the Internet? Where Is My Data?

Only to check GitHub for updates, when you click **Check Now** or turn on **Check for updates automatically** (off by default): [How Update Checks Work](Updating-and-Uninstalling.md#how-update-checks-work). Data: [Data on Your Mac](Permissions-and-Security.md#data-on-your-mac).

### How Do I Update OJD?

Replace the app with the later disk image from [GitHub Releases](https://github.com/xsyetopz/OpenJoystickDriver/releases). Your data stays ([details](Updating-and-Uninstalling.md#install-an-update)).

### How Do I Remove OJD?

Quit OJD and trash it ([Uninstall](Updating-and-Uninstalling.md#uninstall)). Data stays.

## Getting Help

### Something Doesn't Work. What Now?

Try [Troubleshooting](Troubleshooting.md), then [Known Issues](Known-Issues.md).

### How Do I Report a Bug and Get a Fix?

Choose **Help** > **Copy Support Report**, read it, and paste it into a GitHub issue ([Reporting a Bug](Reporting-a-Bug.md)). The fix ships in the next tester build or release, linked from the issue ([Get a Fix](Updating-and-Uninstalling.md#get-a-fix)).

## Further Reading

[Getting Started](Getting-Started.md) and [Glossary](Glossary.md).
