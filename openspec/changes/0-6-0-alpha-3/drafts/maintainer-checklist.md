# Maintainer hardware checklist: 8BitDo Ultimate 2C

Tasks 2.1, 2.2, 2.3, 2.7, 2.11. Each capture goes in the folder named in its step. Run `ojd controller list` first and use the `VVVV:PPPP` it prints. Not a GitHub comment: it is a list for the person holding the pad.

## 2.1 Receiver captures

1. Link the pad to the receiver as `2DC8:301C` (DInput). In the 8BitDo app, cancel the L4 assignment. R4 is already cancelled.
2. Press only L4 for 20 seconds:
   ```
   ojd controller capture 2DC8:301C --duration 20 > evidence/2c-receiver-301c/rear-l4-cancelled-20s.txt
   ```
3. Link the pad as `2DC8:310A` (XInput). Assign neither rear button. Press only L4, then only R4, 20 seconds each:
   ```
   ojd controller capture 2DC8:310A --duration 20 > evidence/2c-receiver-310a/rear-l4-unassigned-20s.txt
   ojd controller capture 2DC8:310A --duration 20 > evidence/2c-receiver-310a/rear-r4-unassigned-20s.txt
   ```

## 2.2 Battery at a second charge level

Charge the pad to a level different from the one in `evidence/2c-bluetooth-301b/`. Connect over Bluetooth LE, then:

```
ojd controller capture 2DC8:301B --duration 10 > evidence/2c-bluetooth-301b/battery-second-level-10s.txt
ojd controller show 2DC8:301B
```

Write the charge level you read on the pad in the file name or beside the file.

## 2.3 Rear buttons by cable

Plug the pad in by USB cable. Run `ojd controller list` and note the identity. Press L4 only, then R4 only, 20 seconds each:

```
ojd controller capture VVVV:PPPP --duration 20 > evidence/2c-wired/rear-l4-20s.txt
ojd controller capture VVVV:PPPP --duration 20 > evidence/2c-wired/rear-r4-20s.txt
```

Replace `VVVV:PPPP` with the identity listed. Record per mode, in `docs/testing/8bitdo-ultimate-2c.md`, whether each rear button has its own bit.

## 2.7 Modes that produce 2DC8:301D and 2DC8:3109

For each pad mode, switch the pad, then run:

```
ojd controller list
```

If `2DC8:301D` or `2DC8:3109` appears, capture it:

```
ojd controller capture 2DC8:301D --duration 60 > evidence/2c-wired-301d/ordered-controls-60s.txt
ojd controller capture 2DC8:3109 --duration 60 > evidence/2c-adapter-3109/ordered-controls-60s.txt
```

Press the controls in the order the other captures use. If no mode produces an identity, leave its row "Unverified" and say which modes you tried.

## 2.11 Bluetooth LE served by OJD

Use the build that carries the `server` change for `2DC8:301B`.

1. Connect the pad over Bluetooth LE with an empty `Controllers/` folder.
2. Save the state:
   ```
   ojd controller show 2DC8:301B > evidence/2c-bluetooth-301b/controller-show-empty-folder.txt
   ```
3. Serve it as the virtual gamepad:
   ```
   ojd virtual set game-controller-compatible 2DC8:301B
   ```
4. Run `just diagnose-gamecontroller`, press each control, and save its output beside the evidence. The probe should list one controller and each button should change it.
5. Press Guide with `OpenJoystickDriverGameControllerViewer` in front. Record whether it shows Home.
6. Link the pad to the receiver as `2DC8:301C` and run the same probe. Record whether GameController lists the pad.
