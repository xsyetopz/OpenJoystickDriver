Could you capture what the controller sends on macOS? I need this for `2DC8:2027` (8BitDo Ultimate C Wired for Xbox) and, if you own it, `2DC8:2019`. Capture each separately.

I add a record only from a capture, so I cannot add either pad without one.

1. Install the tester build posted in Discord `#tester-builds`.
2. Plug the pad in. Run:
   ```
   ojd controller list
   ojd status
   ```
   Copy both outputs. If the pad does not appear in `ojd controller list`, say so and go to step 4.
3. If it appears, press each control once and run:
   ```
   ojd controller capture 2DC8:2027 --duration 60 > capture-2027.txt
   ```
   Use `2DC8:2019` for the other pad. Press A, B, X, Y, LB, RB, LT, RT, View, Menu, Guide, L3, R3, D-pad up, right, down, left, then both sticks around.
4. Run:
   ```
   ojd diagnose --output support-2027.txt
   ojd log export ojd-log-2027.txt --lines 500
   ```
   Read both files before you share them.
5. Attach the outputs and files here. State which controller each belongs to, and whether the pad went dark (no input in any app) after it was plugged in.
