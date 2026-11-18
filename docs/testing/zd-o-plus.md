# ZD O+ in Switch Mode

ZD pads with USB vendor `11C0`, such as the ZD O+, can start in Switch mode as `057E:2009` (a Switch Pro Controller ID, USB serial `000000000001`). OJD then binds them as a Pro Controller and sends its startup reports. These steps show whether OJD or macOS keeps the pad in Switch mode. Not yet run; any `11C0` ZD pad owner can.

## What to Send Back

Run every step twice, with OJD stopped (`ojd service stop`) and running (`ojd service start`), replugging after each change. Per run, send:

1. Its ID: `11C0:5505` or `057E:2009`.
2. Its USB device entry with USB serial, manufacturer, product string, and `bcdDevice`:

   ```bash
   ioreg -l -w0 -r -c IOUSBHostDevice
   ```

   Paste the entry whose `idVendor` is `4544` (`11C0`) or `1406` (`057E`).
3. Its interface entries (endpoints):

   ```bash
   ioreg -l -w0 -r -c IOUSBHostInterface
   ```

   Paste every pad entry. If none shows a `bInterval`, say so.
4. `ojd diagnose` output (OJD-running run only).

Say whether it shows `11C0:5505` when nothing sends a handshake (OJD stopped). If it has a mode switch or button combination, name the mode as its manual does.

Report in an issue with the pad's name and both IDs.
