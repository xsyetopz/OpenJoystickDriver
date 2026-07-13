import AppKit
import OpenJoystickDriverKit
import SwiftUI

extension MenuBarPopoverView {
  var outputDetailsCard: some View {
    OJDCard(title: L10n.string("output.detailsCardTitle")) {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          L10n.string("output.mode"),
          selection: Binding(
            get: { model.virtualDeviceMode },
            set: { newValue in Task { await model.setVirtualDeviceMode(newValue) } }
          )
        ) {
          Text(L10n.string("output.auto")).tag(VirtualDeviceMode.auto.rawValue)
          Text(L10n.string("output.driverKit")).tag(VirtualDeviceMode.driverKit.rawValue)
          Text(L10n.string("output.compatibility")).tag(VirtualDeviceMode.compatUserSpace.rawValue)
          if model.developerMode {
            Text(L10n.string("output.both")).tag(VirtualDeviceMode.both.rawValue)
          }
        }.pickerStyle(.segmented).disabled(!model.serviceConnected)

        Toggle(
          L10n.string("output.userSpace"),
          isOn: Binding(
            get: { model.userSpaceVirtualDeviceEnabled },
            set: { enabled in Task { await model.setUserSpaceVirtualDeviceEnabled(enabled) } }
          )
        ).toggleStyle(.checkbox).disabled(!model.serviceConnected)

        Picker(
          L10n.string("output.active"),
          selection: Binding(
            get: { model.outputMode },
            set: { mode in Task { await model.setOutputMode(mode) } }
          )
        ) {
          Text(L10n.string("output.driverKit")).tag(
            CompositeOutputDispatcher.Mode.primaryOnly.rawValue
          )
          Text(L10n.string("output.compatibility")).tag(
            CompositeOutputDispatcher.Mode.secondaryOnly.rawValue
          )
          Text(L10n.string("output.both")).tag(CompositeOutputDispatcher.Mode.both.rawValue)
        }.pickerStyle(.segmented).disabled(!model.serviceConnected)

        VStack(alignment: .leading, spacing: 3) {
          statusLine(L10n.string("output.active"), activeOutputLabel)
          statusLine(
            L10n.string("output.backend"),
            model.userSpaceVirtualDeviceStatus,
            warning: model.userSpaceVirtualDeviceStatus.hasPrefix("error:")
          )
          statusLine(
            L10n.string("output.gameController"),
            gameControllerSupportLabel,
            success: gameControllerSupportLabel == L10n.string("gameController.yes")
          )
          if let s = model.virtualDeviceDiagnostics?.driverKitOutputStats {
            statusLine(
              L10n.string("output.driverKitReports"),
              "ok \(s.successes), fail \(s.failures), last \(s.lastErrorHex ?? "none")"
            )
          }
        }

        HStack {
          Spacer()
          SwiftUI.Button(L10n.string("settings.reset")) { pendingConfirmation = .resetSettings }
            .buttonStyle(.borderless).controlSize(.small).foregroundColor(.secondary).disabled(
              !model.serviceConnected
            )
        }
      }
    }
  }

  func statusLine(_ label: String, _ value: String, success: Bool = false, warning: Bool = false)
    -> some View
  {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label).font(.caption).foregroundColor(.secondary).frame(width: 96, alignment: .leading)
      Text(value).font(.caption).foregroundColor(
        success ? .green : (warning ? .orange : .secondary)
      ).fixedSize(horizontal: false, vertical: true)
    }
  }

  var activeOutputLabel: String {
    switch model.outputMode {
    case CompositeOutputDispatcher.Mode.primaryOnly.rawValue: return L10n.string("output.driverKit")
    case CompositeOutputDispatcher.Mode.secondaryOnly.rawValue:
      return L10n.string("output.compatibility")
    case CompositeOutputDispatcher.Mode.both.rawValue: return L10n.string("output.both")
    default: return L10n.string("output.unknown")
    }
  }

  var compatibilityIdentityLabel: String {
    switch model.compatibilityIdentity {
    case CompatibilityIdentity.sdl2_3.rawValue: return L10n.string("identity.sdlShort")
    case CompatibilityIdentity.appleGameController.rawValue:
      return L10n.string("output.gameController")
    case CompatibilityIdentity.genericHID.rawValue: return L10n.string("profile.genericHID")
    case CompatibilityIdentity.x360HID.rawValue: return L10n.string("identity.xbox360Short")
    case CompatibilityIdentity.xoneHID.rawValue: return L10n.string("identity.xboxOneShort")
    default: return model.compatibilityIdentity
    }
  }

  var selfTestRow: some View {
    OJDCard(title: L10n.string("selfTest.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(L10n.string("selfTest.description")).font(.caption).foregroundColor(.secondary)
          Spacer()
          SwiftUI.Button(
            runningSelfTest ? L10n.string("selfTest.running") : L10n.string("selfTest.run5s")
          ) {
            runningSelfTest = true
            Task {
              await model.syncFromApplicationServiceNow()
              await model.runVirtualDeviceSelfTest(seconds: 5)
              runningSelfTest = false
            }
          }.buttonStyle(.borderless).controlSize(.small).disabled(
            !model.serviceConnected || runningSelfTest
          )
        }
        if let t = model.virtualDeviceSelfTest {
          VStack(alignment: .leading, spacing: 3) {
            let relayVerdict = t.driverKitRelayVerdict
            statusLine(
              L10n.string("selfTest.driverKit"),
              relayVerdict.rawValue,
              success: relayVerdict == .passed,
              warning: relayVerdict != .passed
            )
            statusLine(
              L10n.string("output.driverKitReports"),
              "value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)"
            )
            if let delta = t.driverKitInputReportDelta {
              statusLine(L10n.string("output.ioregInput"), "Δ \(delta)")
            }
            if let delta = t.driverKitSetReportSuccessDelta {
              statusLine(L10n.string("output.serviceSetReport"), "ok Δ \(delta)")
            }
            statusLine(
              L10n.string("output.userSpace"),
              "value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)"
            )
            if t.userSpaceRequired {
              let verdict = t.userSpaceVerdict
              statusLine(
                "Compatibility output",
                "\(verdict.rawValue): \(t.userSpaceStatus)",
                success: verdict == .passed,
                warning: verdict != .passed
              )
            }
          }
        } else {
          Text(L10n.string("selfTest.pressButtons")).font(.caption).foregroundColor(.secondary)
        }
      }
    }
  }

  var inputTestRow: some View {
    OJDCard(title: L10n.string("input.title")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(L10n.string("inputTest.description")).font(.caption).foregroundColor(.secondary)
          Spacer()
          SwiftUI.Button(L10n.string("button.openInputTest")) { inputTester.show(model: model) }
            .controlSize(.small).disabled(!model.serviceConnected)
        }
      }
    }
  }

}
