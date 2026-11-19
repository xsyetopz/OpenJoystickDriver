# ZD O+ in Switch Mode

ZD controllers with USB vendor `11C0`, such as the ZD O+, can start up pretending to be a Switch Pro Controller: `057E:2009`, with USB serial `000000000001`. OJD then treats them as a Pro Controller and sends its startup reports. These steps find out who keeps the controller in Switch mode, OJD or macOS. Nobody has run them yet. Anyone with an `11C0` ZD controller can.

## What to Send Back

Run every step twice: once with OJD stopped (`ojd service stop`) and once with it running (`ojd service start`). Unplug and plug back in after each change. For each run, send:

1. Its ID: `11C0:5505` or `057E:2009`.
2. Its USB device entry, with USB serial, manufacturer, product name, and `bcdDevice`:

   ```bash
   ioreg -l -w0 -r -c IOUSBHostDevice
   ```

   Paste the entry whose `idVendor` is `4544` (`11C0`) or `1406` (`057E`).
3. Its interface entries, which list the endpoints:

   ```bash
   ioreg -l -w0 -r -c IOUSBHostInterface
   ```

   Paste every entry for the controller. If none shows a `bInterval`, say so.
4. The `ojd diagnose` output, from the run with OJD running only.

Say whether it shows `11C0:5505` when nothing says hello to it (OJD stopped). If it has a mode switch or a button combination, name the mode the way its manual does.

Report it in an issue with the controller's name and both IDs.
