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

  var appleGameControllerCatalogRow: some View {
    OJDCard(title: L10n.string("appleCatalog.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 10) {
          Text(L10n.string("appleCatalog.description")).font(.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
          SwiftUI.Button(
            model.appleGameControllerAuditRunning
              ? L10n.string("appleCatalog.scanning") : L10n.string("appleCatalog.scan")
          ) { Task { await model.runAppleGameControllerAudit() } }.controlSize(.small).disabled(
            model.appleGameControllerAuditRunning
          )
        }

        if let audit = model.appleGameControllerAudit {
          statusLine(
            L10n.string("appleCatalog.version"),
            audit.bundleVersions.isEmpty
              ? L10n.string("appleCatalog.unavailable")
              : audit.bundleVersions.joined(separator: ", ")
          )
          statusLine(L10n.string("appleCatalog.appleEntries"), "\(audit.appleExactDeviceCount)")
          statusLine(
            L10n.string("appleCatalog.ojdListed"),
            "\(audit.catalogListedOJDRecordCount)/\(audit.ojdRecordCount)",
            warning: audit.source == .unavailable
          )
          statusLine(
            L10n.string("appleCatalog.compatibilityListed"),
            "\(audit.appleBackedCompatibilityProfileCount)/"
              + "\(audit.hardwareSpoofCompatibilityProfileCount)",
            warning: audit.appleBackedCompatibilityProfileCount
              < audit.hardwareSpoofCompatibilityProfileCount
          )
          Text(L10n.string("appleCatalog.caveat")).font(.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  var browserGamepadDiagnosticRow: some View {
    OJDCard(title: L10n.string("browserDiagnostic.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.string("browserDiagnostic.description")).font(.caption).foregroundColor(
          .secondary
        ).fixedSize(horizontal: false, vertical: true)

        Picker(L10n.string("browserDiagnostic.browser"), selection: $browserGamepadTarget) {
          ForEach(BrowserGamepadTarget.allCases, id: \.rawValue) { target in
            Text(browserGamepadTargetLabel(target)).tag(target)
          }
        }.disabled(model.browserGamepadDiagnosticRunning)

        HStack(spacing: 10) {
          Text(L10n.string("browserDiagnostic.port")).font(.caption).foregroundColor(.secondary)
          TextField(
            "",
            text: Binding(
              get: { String(browserGamepadPort) },
              set: { value in if let port = Int(value) { browserGamepadPort = port } }
            )
          ).frame(width: 68).disabled(model.browserGamepadDiagnosticRunning)

          Stepper(
            L10n.string("browserDiagnostic.duration", browserGamepadSeconds),
            value: $browserGamepadSeconds,
            in: 1...3_600,
            step: 1
          ).font(.caption).disabled(model.browserGamepadDiagnosticRunning)
        }

        HStack(spacing: 8) {
          SwiftUI.Button(
            model.browserGamepadDiagnosticRunning
              ? L10n.string("browserDiagnostic.stop") : L10n.string("browserDiagnostic.run")
          ) {
            if model.browserGamepadDiagnosticRunning {
              model.stopBrowserGamepadDiagnostic()
            } else {
              Task {
                await model.startBrowserGamepadDiagnostic(
                  port: browserGamepadPort,
                  seconds: browserGamepadSeconds,
                  target: browserGamepadTarget
                )
              }
            }
          }.controlSize(.small)

          if model.browserGamepadDiagnosticRunning {
            Text(L10n.string("browserDiagnostic.running")).font(.caption.weight(.semibold))
              .foregroundColor(.green)
          }
        }

        if model.browserGamepadSnapshotCount > 0 {
          Text(L10n.string("browserDiagnostic.snapshotCount", model.browserGamepadSnapshotCount))
            .font(.caption).foregroundColor(.secondary)
        }

        if let url = model.browserGamepadDiagnosticURL {
          Text(L10n.string("browserDiagnostic.url", url.absoluteString)).font(.caption)
            .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if let error = model.browserGamepadDiagnosticError {
          Text(error).font(.caption).foregroundColor(.orange).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
      }
    }
  }

  private func browserGamepadTargetLabel(_ target: BrowserGamepadTarget) -> String {
    switch target {
    case .none: return L10n.string("browserDiagnostic.target.none")
    case .systemDefault: return L10n.string("browserDiagnostic.target.default")
    case .safari: return "Safari"
    case .chrome: return "Google Chrome"
    case .firefox: return "Firefox"
    case .all: return L10n.string("browserDiagnostic.target.all")
    }
  }

  var supportReportRow: some View {
    OJDCard(title: L10n.string("supportReport.cardTitle")) {
      HStack(alignment: .top, spacing: 10) {
        Text(L10n.string("supportReport.description")).font(.caption).foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        SwiftUI.Button(
          model.creatingSupportReport
            ? L10n.string("supportReport.saving") : L10n.string("supportReport.save")
        ) { Task { await model.saveSupportReport() } }.controlSize(.small).disabled(
          model.creatingSupportReport
        )
      }
    }
  }

  var advancedToggle: some View {
    SwiftUI.Button {
      showAdvanced.toggle()
    } label: {
      HStack {
        Text(
          showAdvanced ? L10n.string("advanced.hideDetails") : L10n.string("advanced.showDetails")
        )
        Spacer()
        Text(showAdvanced ? L10n.string("advanced.collapse") : L10n.string("advanced.expand"))
      }.font(.caption.weight(.semibold)).foregroundColor(.secondary).padding(.horizontal, 12)
        .padding(.vertical, 8).background(
          RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08))
        )
    }.buttonStyle(.plain)
  }

  var footerRow: some View {
    HStack(spacing: 10) {
      SwiftUI.Button(L10n.string("app.refresh")) { Task { await model.syncFromDaemonNow() } }
        .buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("button.showLog")) {
        for stream in DaemonLogStream.allCases {
          NSWorkspace.shared.selectFile(
            DaemonLogService.url(for: stream).path,
            inFileViewerRootedAtPath: ""
          )
        }
      }.buttonStyle(.borderless)

      SwiftUI.Button(L10n.string("app.quit")) { NSApplication.shared.terminate(nil) }.buttonStyle(
        .borderless
      )

      Spacer()
    }.font(.caption)
  }

  var updateRow: some View {
    OJDCard(title: L10n.string("updates.cardTitle")) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(updateStatusLine).font(.caption).foregroundColor(updateStatusColor).fixedSize(
            horizontal: false,
            vertical: true
          )
          Spacer()
          SwiftUI.Button(updateButtonTitle) { Task { await model.checkForUpdates() } }.buttonStyle(
            .borderless
          ).controlSize(.small).disabled(model.updateCheckState == .checking)
        }

        if !model.sparkleUpdates.isConfigured {
          Toggle(L10n.string("updates.includePrereleases"), isOn: $model.includePrereleaseUpdates)
            .font(.caption).toggleStyle(.checkbox).disabled(model.updateCheckState == .checking)
        }

        if case .available(let info) = model.updateCheckState {
          HStack(spacing: 8) {
            Text(L10n.string("updates.available", info.tagName)).font(.caption).foregroundColor(
              .orange
            )
            Spacer()
            SwiftUI.Button(L10n.string("app.open")) { model.openLatestRelease() }.buttonStyle(
              .borderless
            ).controlSize(.small)
          }
        }
      }
    }
  }

  var updateButtonTitle: String {
    model.updateCheckState == .checking
      ? L10n.string("updates.checking") : L10n.string("updates.check")
  }

  var updateStatusLine: String {
    if model.sparkleUpdates.isConfigured {
      return L10n.string("updates.currentVersion", model.appVersion)
    }

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
