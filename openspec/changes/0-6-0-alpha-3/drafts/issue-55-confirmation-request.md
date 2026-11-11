Thanks for pull request #56 and the endpoint findings.

I am taking the Elite Series 1 endpoints (`0x81` in, `0x01` out) into the `045E:02E3` record. Could you confirm them on a tester build?

1. Install the tester build posted in Discord `#tester-builds`.
2. Plug the Elite Series 1 in by cable and run:
   ```
   ojd controller list
   ojd controller show 045E:02E3
   ```
3. Press each control once while this runs:
   ```
   ojd controller watch 045E:02E3 --duration 60
   ```
4. Check the crash from your report. Run:
   ```
   ojd controller rumble 045E:02E3 --left 100 --right 100 --duration 2
   ```
   Tell me whether the service stays up and the pad vibrates.
5. Run:
   ```
   ojd diagnose --output support-02e3.txt
   ```
   Read the file before you share it.
6. Attach the outputs and say which controls work.
