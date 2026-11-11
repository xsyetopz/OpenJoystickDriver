Could you confirm the Xbox One controller (model 1537, `045E:02D1`) on a tester build that has no extension?

I want to know whether OJD reads it and serves it with no extension installed.

1. Install the tester build posted in Discord `#tester-builds`. It ships without the transport extension.
2. Check that no extension is active:
   ```
   ojd transport-extension status
   ```
   It should show `bundle: Missing` or `registration: Absent` or `Inactive`. If it shows `Active`, run `ojd transport-extension deactivate` and check again.
3. Plug the controller in and run:
   ```
   ojd controller list
   ojd controller show 045E:02D1
   ```
4. Press each control once during:
   ```
   ojd controller watch 045E:02D1 --duration 60
   ```
5. Run:
   ```
   ojd diagnose --output support-02d1.txt
   ```
   Read `support-02d1.txt` before you share it.
6. Attach the outputs and tell me which controls work and which do not.

If you own a `045E:02DD`, `045E:02E3` or `045E:0B0A`, run the same steps with that identity in place of `045E:02D1` and say which one you tested.
