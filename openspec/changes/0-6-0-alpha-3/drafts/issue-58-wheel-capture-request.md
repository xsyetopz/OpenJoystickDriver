Could you capture every pedal and button on the Ferrari 458 Spider (`044F:B671`)? I will write the layout from your packets and check it with `ojd record test`, so I need each control pressed on its own.

1. Install the tester build posted in Discord `#tester-builds`.
2. Connect the wheel and run:
   ```
   ojd controller list
   ojd controller show 044F:B671
   ```
3. Start a capture and work through the controls in this order, pausing about two seconds between steps:
   ```
   ojd controller capture 044F:B671 --duration 120 > wheel-capture.txt
   ```
   - Hands off for 3 seconds.
   - Wheel fully left, back to center, fully right, back to center.
   - Brake pedal from released to fully pressed and back.
   - Accelerator pedal from released to fully pressed and back.
   - Clutch pedal, if the wheel has one, the same way.
   - Every button, one at a time, then each paddle and each D-pad direction.
4. Write down the order you pressed them in and attach it with `wheel-capture.txt`.
5. Run:
   ```
   ojd diagnose --output support-b671.txt
   ```
   Read the file before you share it, then attach it.
