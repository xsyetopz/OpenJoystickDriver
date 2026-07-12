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
        }.pickerStyle(.segmented).disabled(!model.daemonConnected)

        Toggle(
          L10n.string("output.userSpace"),
          isOn: Binding(
            get: { model.userSpaceVirtualDeviceEnabled },
            set: { enabled in Task { await model.setUserSpaceVirtualDeviceEnabled(enabled) } }
          )
        ).toggleStyle(.checkbox).disabled(!model.daemonConnected)

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
        }.pickerStyle(.segmented).disabled(!model.daemonConnected)

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
              !model.daemonConnected
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
              await model.syncFromDaemonNow()
              if model.daemonHealth?.isInefficientKillLoop == true {
                model.daemonError = L10n.string("selfTest.daemonKillLoop")
                runningSelfTest = false
                return
              }
              await model.runVirtualDeviceSelfTest(seconds: 5)
              runningSelfTest = false
            }
          }.buttonStyle(.borderless).controlSize(.small).disabled(
            !model.daemonConnected || runningSelfTest
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
              statusLine(L10n.string("output.daemonSetReport"), "ok Δ \(delta)")
            }
            statusLine(
              L10n.string("output.userSpace"),
              "value \(t.userSpaceValueEvents), report \(t.userSpaceReportEvents)"
            )
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
            .controlSize(.small).disabled(!model.daemonConnected)
        }
      }
    }
  }

  var runtimeHealthRow: some View {
    OJDCard(title: L10n.string("runtimeHealth.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.string("runtimeHealth.description")).font(.caption).foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            runtimeIntegerField(
              L10n.string("runtimeHealth.seconds"),
              value: $runtimeHealthSeconds,
              width: 58
            )
            runtimeIntegerField(
              L10n.string("runtimeHealth.intervalMs"),
              value: $runtimeHealthIntervalMilliseconds,
              width: 64
            )
          }
          HStack(spacing: 8) {
            runtimeIntegerField(
              L10n.string("runtimeHealth.rssLimitMiB"),
              value: $runtimeHealthResidentLimitMiB,
              width: 58
            )
            runtimeIntegerField(
              L10n.string("runtimeHealth.footprintLimitMiB"),
              value: $runtimeHealthFootprintLimitMiB,
              width: 58
            )
          }
        }.disabled(model.runtimeHealthRunning)

        HStack {
          Text(L10n.string("runtimeHealth.limitDisabledHint")).font(.caption).foregroundColor(
            .secondary
          )
          Spacer()
          SwiftUI.Button(
            model.runtimeHealthRunning
              ? L10n.string("runtimeHealth.stop") : L10n.string("runtimeHealth.run")
          ) {
            if model.runtimeHealthRunning {
              model.stopRuntimeHealthCheck()
            } else {
              Task {
                await model.runRuntimeHealthCheck(
                  seconds: runtimeHealthSeconds,
                  intervalMilliseconds: runtimeHealthIntervalMilliseconds,
                  residentLimitMiB: runtimeHealthResidentLimitMiB,
                  physicalFootprintLimitMiB: runtimeHealthFootprintLimitMiB
                )
              }
            }
          }.controlSize(.small).disabled(
            !model.runtimeHealthRunning && model.daemonHealth?.pid == nil
          )
        }

        if let summary = model.runtimeHealthSummary {
          statusLine(
            L10n.string("runtimeHealth.rss"),
            "\(runtimeMebibytes(summary.firstResidentBytes)) -> "
              + "\(runtimeMebibytes(summary.lastResidentBytes)) MiB; "
              + "peak \(runtimeMebibytes(summary.peakResidentBytes))"
          )
          statusLine(
            L10n.string("runtimeHealth.footprint"),
            "\(runtimeMebibytes(summary.firstPhysicalFootprintBytes)) -> "
              + "\(runtimeMebibytes(summary.lastPhysicalFootprintBytes)) MiB"
          )
          statusLine(
            L10n.string("runtimeHealth.growthRate"),
            "\(runtimeSignedMebibytes(summary.residentGrowthBytesPerHour)) MiB/hour"
          )
          statusLine(
            L10n.string("runtimeHealth.resources"),
            "FD \(summary.firstFileDescriptorCount)->\(summary.lastFileDescriptorCount), "
              + "threads \(summary.firstThreadCount)->\(summary.lastThreadCount)"
          )
          statusLine(
            L10n.string("runtimeHealth.cpu"),
            String(format: "%.2f%%", summary.averageCPUPercent)
          )
          statusLine(
            L10n.string("runtimeHealth.verdict"),
            runtimeHealthSoakVerdictLabel(summary.soakVerdict),
            success: summary.soakVerdict == .stable,
            warning: summary.soakVerdict != .stable
          )
        }
      }
    }
  }

  private func runtimeIntegerField(_ label: String, value: Binding<Int>, width: CGFloat)
    -> some View
  {
    HStack(spacing: 4) {
      Text(label).font(.caption).foregroundColor(.secondary)
      TextField(
        "",
        text: Binding(
          get: { String(value.wrappedValue) },
          set: { text in if let number = Int(text) { value.wrappedValue = number } }
        )
      ).frame(width: width)
    }
  }

  private func runtimeMebibytes(_ bytes: UInt64) -> String {
    String(format: "%.2f", Double(bytes) / 1_048_576)
  }

  private func runtimeSignedMebibytes(_ bytesPerHour: Double) -> String {
    let value = bytesPerHour / 1_048_576
    return String(format: value >= 0 ? "+%.2f" : "%.2f", value)
  }

  private func runtimeHealthSoakVerdictLabel(_ verdict: RuntimeSoakVerdict) -> String {
    switch verdict {
    case .stable: return L10n.string("runtimeHealth.stable")
    case .memoryGrowthObserved: return L10n.string("runtimeHealth.memoryGrowth")
    case .resourceGrowthObserved: return L10n.string("runtimeHealth.resourceGrowth")
    case .residentLimitExceeded: return L10n.string("runtimeHealth.limitExceeded")
    case .physicalFootprintLimitExceeded: return L10n.string("runtimeHealth.footprintLimitExceeded")
    case .insufficientData: return L10n.string("runtimeHealth.insufficient")
    }
  }
}
