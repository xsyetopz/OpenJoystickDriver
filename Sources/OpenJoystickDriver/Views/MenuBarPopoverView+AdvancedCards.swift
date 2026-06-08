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
        }
        .pickerStyle(.segmented)
        .disabled(!model.daemonConnected)

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
      }
    }
  }

  func statusLine(
    _ label: String,
    _ value: String,
    success: Bool = false,
    warning: Bool = false
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 96, alignment: .leading)
      Text(value)
        .font(.caption)
        .foregroundColor(success ? .green : (warning ? .orange : .secondary))
        .fixedSize(horizontal: false, vertical: true)
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
    case CompatibilityIdentity.sdl2_3.rawValue:
      return L10n.string("identity.sdlShort")
    case CompatibilityIdentity.appleGameController.rawValue:
      return L10n.string("output.gameController")
    case CompatibilityIdentity.genericHID.rawValue: return L10n.string("profile.genericHID")
    case CompatibilityIdentity.x360HID.rawValue:
      return L10n.string("identity.xbox360Short")
    case CompatibilityIdentity.xoneHID.rawValue:
      return L10n.string("identity.xboxOneShort")
    default: return model.compatibilityIdentity
    }
  }

  var selfTestRow: some View {
    OJDCard(title: L10n.string("selfTest.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L10n.string("selfTest.description"))
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        SwiftUI.Button(
          runningSelfTest ? L10n.string("selfTest.running") : L10n.string("selfTest.run5s")
        ) {
          runningSelfTest = true
          Task {
              await model.syncFromDaemonNow()
            if model.daemonHealth?.isInefficientKillLoop == true {
              model.daemonError =
                L10n.string("selfTest.daemonKillLoop")
              runningSelfTest = false
              return
            }
            await model.runVirtualDeviceSelfTest(seconds: 5)
            runningSelfTest = false
          }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!model.daemonConnected || runningSelfTest)
      }
      if let t = model.virtualDeviceSelfTest {
        VStack(alignment: .leading, spacing: 3) {
          statusLine(
            L10n.string("output.driverKit"),
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
        Text(L10n.string("selfTest.pressButtons"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      }
    }
  }

  var inputTestRow: some View {
    OJDCard(title: L10n.string("input.title")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(L10n.string("inputTest.description"))
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          SwiftUI.Button(L10n.string("button.openInputTest")) {
            inputTester.show(model: model)
          }
          .controlSize(.small)
          .disabled(!model.daemonConnected)
        }
      }
    }
  }

  var advancedToggle: some View {
    SwiftUI.Button {
      showAdvanced.toggle()
    } label: {
      HStack {
        Text(
          showAdvanced
            ? L10n.string("advanced.hideDetails")
            : L10n.string("advanced.showDetails")
        )
        Spacer()
        Text(showAdvanced ? L10n.string("advanced.collapse") : L10n.string("advanced.expand"))
      }
      .font(.caption.weight(.semibold))
      .foregroundColor(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.secondary.opacity(0.08))
      )
    }
    .buttonStyle(.plain)
  }

  var footerRow: some View {
    HStack(spacing: 10) {
      SwiftUI.Button(L10n.string("app.refresh")) {
        Task {
          await model.syncFromDaemonNow()
        }
      }
      .buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("button.showLog")) {
        NSWorkspace.shared.selectFile(
          "/tmp/com.openjoystickdriver.daemon.out",
          inFileViewerRootedAtPath: ""
        )
      }
      .buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("app.quit")) { NSApplication.shared.terminate(nil) }
        .buttonStyle(.borderless)

      Spacer()
    }
    .font(.caption)
  }

  var updateRow: some View {
    OJDCard(title: L10n.string("updates.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(updateStatusLine)
            .font(.caption)
            .foregroundColor(updateStatusColor)
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
          SwiftUI.Button(updateButtonTitle) {
            Task { await model.checkForUpdates() }
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .disabled(model.updateCheckState == .checking)
        }

        Toggle(L10n.string("updates.includePrereleases"), isOn: $model.includePrereleaseUpdates)
          .font(.caption)
          .toggleStyle(.checkbox)
          .disabled(model.updateCheckState == .checking)

        if case .available(let info) = model.updateCheckState {
          HStack(spacing: 8) {
            Text(L10n.string("updates.available", info.tagName))
              .font(.caption)
              .foregroundColor(.orange)
            Spacer()
            SwiftUI.Button(L10n.string("app.open")) { model.openLatestRelease() }
              .buttonStyle(.borderless)
              .controlSize(.small)
          }
        }
      }
    }
  }

  var updateButtonTitle: String {
    model.updateCheckState == .checking
      ? L10n.string("updates.checking")
      : L10n.string("updates.check")
  }

  var updateStatusLine: String {
    switch model.updateCheckState {
    case .idle: return L10n.string("updates.currentVersion", model.appVersion)
    case .checking: return L10n.string("updates.checkingGithub")
    case .upToDate(let version): return L10n.string("updates.current", version)
    case .available: return L10n.string("updates.updateAvailable")
    case .failed(let message): return L10n.string("updates.checkFailed", message)
    }
  }

  var updateStatusColor: Color {
    switch model.updateCheckState {
    case .upToDate: return .green
    case .available, .failed: return .orange
    default: return .secondary
    }
  }
}
