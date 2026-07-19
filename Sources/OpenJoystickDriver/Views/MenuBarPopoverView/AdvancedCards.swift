import AppKit
import OpenJoystickDriverKit
import SwiftUI

extension MenuBarPopoverView {
  var outputDetailsCard: some View {
    OJDCard(title: L10n.string("output.detailsCardTitle")) {
      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
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
              "\(relayVerdict.rawValue) (\(t.driverKitRequired ? "required" : "optional"))",
              success: relayVerdict == .passed,
              warning: t.driverKitRequired && relayVerdict != .passed
            )
            statusLine(
              L10n.string("output.driverKitReports"),
              "value \(t.driverKitValueEvents), report \(t.driverKitReportEvents)"
            )
            if let delta = t.driverKitInputReportDelta {
              statusLine(L10n.string("output.ioregInput"), "Δ \(delta)")
            }
            if let delta = t.driverKitSubmissionSuccessDelta {
              statusLine(L10n.string("output.serviceSubmission"), "ok Δ \(delta)")
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
