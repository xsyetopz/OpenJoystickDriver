# Ownership

## Contents

- [Presentation owners](#presentation-owners)
- [Gateway seam](#gateway-seam)
- [Single window and runtime](#single-window-and-runtime)

## Presentation owners

**Definition.** `Sources/OpenJoystickDriverPresentation/` depends on `OpenJoystickDriverKit` only. Its directories are:

| Directory | Owns |
| --- | --- |
| `MenuBar/` | `NSStatusItem`, the shallow menu, and app activation |
| `Settings/Shell/` | the reusable `WindowController`, toolbar panes, and geometry persistence |
| `Settings/{Overview,Preferences,Developer}/` | the pane contents |
| `Controllers/{Inventory,InputTest,MotionCalibration}/` | the connected devices, the input test window, and calibration |
| `Profiles/{List,Editor,Draft,AnalogSheets,Bindings}/` | profile selection, drafts, save and conflict, and capture sheets |
| `InputCapture/` | keyboard capture |
| `Runtime/` | `ApplicationServiceGateway`, `RuntimeViewModel`, `SupportState`, and presentation errors |
| `Components/` | shared rows (`SettingsRows.swift`) and loading, empty, and error views (`StateViews.swift`) |

Tests mirror these directories under `Tests/OpenJoystickDriverPresentationTests/`. The shared stubs are in its `Support/` directory.

**Use when.** Adding a view, view model, or coordinator.

**Do not use when.** The code parses packets, validates profiles, or decides routing. That code belongs in Kit or Service (`ojd-swift-change`), and the view shows the result.

**Verify.** `rg -n '^import OpenJoystickDriver(Service|CLI|USB)' Sources/OpenJoystickDriverPresentation` prints nothing, and `swift build` succeeds.

## Gateway seam

**Definition.** `protocol ApplicationServiceGateway` in `Runtime/ApplicationServiceGateway.swift` is composed from smaller gateway protocols. The production adapter wraps `ApplicationServiceClient`, returns typed payloads, and maps transport failures to stable presentation errors. The full call list is under "Gateway Contract" in `contributing/development/menu-bar-settings-architecture.md`.

**Use when.** A view model needs runtime data or an action.

**Do not use when.** The data is purely presentational, such as a sort order, a selection, or a draft. Keep it in the view model.

**Example.** To add a call:

1. Add the RPC method to Kit, and serve it from Service.
1. Add the requirement to the narrowest gateway protocol.
1. Implement it in the client adapter (`ApplicationServiceClientGateway+Requests.swift`).
1. Implement it in `Tests/OpenJoystickDriverPresentationTests/Support/GatewayStub.swift`.
1. Call it from the view model.

**Cost removed.** Views never see socket paths, raw RPC descriptions, or CLI text. As a result, a transport change does not ripple into the UI.

**Verify.** The new view-model test runs against `GatewayStub`, and the Service RPC test covers the server side.

## Single window and runtime

**Definition.** `HeadlessApplicationHost` in the executable starts one `ApplicationServiceRuntime`, and passes Presentation an injected gateway plus closures such as stop. Presentation does not hold the runtime. `Settings/Shell/WindowController.swift` owns the single reusable settings window. The input test has its own `InputTestWindowController`.

**Use when.** Opening settings from the menu, reopening after close, or adding a secondary window.

**Do not use when.** Never create another runtime, RPC server, or CLI subprocess to fetch data. Add a gateway call instead.

**Verify.** Opening Settings twice brings the same window forward, and the process has one RPC socket listener.
