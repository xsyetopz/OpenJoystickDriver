# ZD O+ in Switch Mode

Some ZD pads with USB vendor `11C0`, such as the ZD O+, come up in Switch mode as `057E:2009`, the ID of a Nintendo Switch Pro Controller, with the USB serial `000000000001`. OJD then binds them as a Pro Controller and sends the Pro Controller startup reports. These steps find out whether OJD's startup reports or macOS keep the pad in Switch mode. Nobody has run them yet. Anyone with a ZD O+ or another `11C0` ZD pad can run them.

## What to send back

Run every step twice: once with OJD stopped (`ojd service stop`) and once with OJD running (`ojd service start`). Unplug the pad and plug it back in after each change. For each run, send:

1. The ID the pad shows: `11C0:5505` or `057E:2009`.
2. The pad's USB device entry, including the USB serial, the manufacturer string, the product string and `bcdDevice`:

   ```bash
   ioreg -l -w0 -r -c IOUSBHostDevice
   ```

   Paste the whole entry whose `idVendor` is `4544` (`11C0`) or `1406` (`057E`).
3. The pad's interface entries, which carry its endpoints:

   ```bash
   ioreg -l -w0 -r -c IOUSBHostInterface
   ```

   Paste every entry for the pad. If no entry shows a `bInterval`, say so.
4. The output of `ojd diagnose` (only for the run with OJD running).

Also say whether the pad comes up as `11C0:5505` when nothing sends it a handshake, that is, in the run with OJD stopped. If the pad has a mode switch or a button combination for its modes, say which mode it was in, as its manual names it.

Report the results in a new issue with the pad's name and both IDs.
