# Permissions

OpenJoystickDriver asks for macOS permissions only when you request them, and each permission has one purpose.

## When OJD asks

OJD requests nothing at start. A request starts only when you do one of these actions:

- Click **Request...** on a card in the **Overview** pane.
- Click **Request Access...** in the menu-bar menu.
- Run the `permissions request` command.

OJD reads the permission state every second. A request result is not treated as a grant. OJD reads the real state again.

## Permission list

| Permission | Purpose | Needed |
| --- | --- | --- |
| Input Monitoring | Read reports from a physical controller | Always |
| Accessibility | Publish the virtual controller | Always |
| Keyboard & pointer | Send keyboard, mouse, or scroll events from a profile | Only when a profile does so |
| Notifications | Show notifications | Optional |

Not verified on hardware: the **Keyboard & pointer** card and the **Accessibility** card may use the same switch in **System Settings**.

OJD does not use camera, microphone, or Full Disk Access permissions. It reads Bluetooth controllers as HID devices, so they need **Input Monitoring**. OJD uses Bluetooth only to disconnect a wireless controller. Whether macOS asks for Bluetooth permission for this is not verified.

## Grant Input Monitoring and Accessibility

1. Open the **Overview** pane, or click the menu-bar icon.
1. Click **Request...** on the **Input Monitoring** card, or click **Request Access...** in the menu.
1. Allow **OpenJoystickDriver** in **System Settings** > **Privacy & Security** > **Input Monitoring**.
1. Repeat for **System Settings** > **Privacy & Security** > **Accessibility**.
1. Click **Restart OpenJoystickDriver** on the **Overview** pane if it appears.

Without **Input Monitoring**, Input Test shows **Input Monitoring permission required**. Without **Accessibility**, the virtual controller does not work.

## Grant Notifications

1. Open **Settings** and turn on a notification toggle, or click **Send Test Notification**.
1. Allow the macOS prompt.

If you denied notifications before, click **Open Notification Settings**. The **Notifications** card shows **Banners off** or **Sound off** when macOS turns those parts off.

## Xbox USB driver approval

The Xbox USB driver extension needs approval, but it is not a privacy permission. For more information, see [Xbox USB driver extension](../connecting-controllers/xbox-usb-driver-extension.md).

## Further reading

- [Security model](security-model.md)
- [Overview pane](../using-the-app/overview-pane.md)
- [Controller not detected](../troubleshooting/controller-not-detected.md)
