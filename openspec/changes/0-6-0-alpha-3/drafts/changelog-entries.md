# Changelog Entries For Task 18.1

Entries the task workers wrote, held here until task 18.1 writes `CHANGELOG.md`.

## Changed

- The app sends the driver extension activation request only after a user action: the banner button, the **Claim** button, `ojd controller claim` for a model that Apple's driver holds, or `ojd transport-extension activate`. Launch, service start and a controller arrival send none. (4.3, 4.5)
- A controller on a model that Apple's driver holds (`045E:02EA`, `045E:0B00`, `045E:0B12`) is listed as served by macOS, with **Claim**, in the Controllers list and in `ojd controller show` (`served-by` and `heldByAppleDriver`). The Microsoft models `045E:02D1`, `045E:02DD`, `045E:02E3` and `045E:0B0A` take the direct route when the extension does not own them. (4.2, 4.4)
- The driver banner shows each state of the request: running with a disabled button, needs approval with a button that opens the approval pane, cancelled, timed out, and failed with the error domain, code and text. It shows only while a connected controller uses the extension route. (4.6)
- The wiki heading `extension` is `transport-extension`. (4.7)
