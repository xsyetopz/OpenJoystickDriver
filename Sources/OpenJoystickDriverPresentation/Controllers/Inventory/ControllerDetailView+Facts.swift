#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ControllerDetailView {

    var body: some View {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            controllerHeader
            controllerSessionAction
            if isBluetooth { wirelessDisconnectAction }
            if let failure = viewModel.controllerActionFailures[device.runtimeIdentifier] {
              controllerActionFailure(failure)
            }
            activeProfileRow
            Divider()
            controllerDetails(
              compact: ControllerDetailLayoutPolicy.factColumnCount(for: proxy.size.width) == 1
            )
            Divider()
            inputTestAction
            if device.physicalOwnership != .nativeGamepad {
              Divider()
              // A per-controller identity collapses Advanced again on a new selection.
              VirtualHIDProfileOverrideView(viewModel: viewModel, device: device).id(
                device.runtimeIdentifier
              )
            }
          }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.ojdAccessibilityLabel(device.name).ojdAccessibilityValue(accessibilityValue).alert(
        isPresented: $confirmsWirelessDisconnect
      ) {
        Alert(
          title: Text(
            OJDLocalized.string(
              "controllers.disconnectWirelessConfirmTitle"
            )
          ),
          message: Text(
            OJDLocalized.formatted(
              "controllers.disconnectWirelessConfirmMessage",
              device.name
            )
          ),
          primaryButton: .destructive(
            Text(
              OJDLocalized.string("controllers.disconnectWirelessConfirm")
            )
          ) { Task { @MainActor in await viewModel.disconnectWirelessController(device) } },
          secondaryButton: .cancel()
        )
      }
    }

    private var isBluetooth: Bool {
      device.connection.caseInsensitiveCompare("Bluetooth") == .orderedSame
    }

    private var wirelessDisconnectAction: some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            OJDLocalized.string(
              "controllers.disconnectWireless"
            )
          ).font(.headline)
          Text(
            OJDLocalized.string(
              "controllers.disconnectWirelessSummary"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 12)
        Button(
          OJDLocalized.string("controllers.disconnectWirelessButton")
        ) { confirmsWirelessDisconnect = true }
      }
    }

    private func controllerActionFailure(_ message: String) -> some View {
      HStack(alignment: .top, spacing: 8) {
        OJDSystemSymbol(
          name: SemanticState.failure.presentation.symbolName,
          fallback: OJDLocalized.string("common.needsAttention")
        ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
        Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }.ojdAccessibilityLabel(
        OJDLocalized.string("common.needsAttention")
      ).ojdAccessibilityValue(message)
    }

    private var inputTestAction: some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(OJDLocalized.string("inputTest.title")).font(.headline)
          Text(
            OJDLocalized.string(
              "inputTest.summary"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        Spacer(minLength: 12)
        Button(OJDLocalized.string("inputTest.open")) {
          openInputTest(device)
        }.disabled(device.sessionState == .suspended)
      }
    }

    private var controllerSessionAction: some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            device.sessionState == .suspended
              ? OJDLocalized.string("controllers.suspended")
              : OJDLocalized.string(
                "controllers.sessionActive"
              )
          ).font(.headline)
          Text(
            device.sessionState == .suspended
              ? OJDLocalized.string(
                "controllers.suspendedSummary"
              )
              : OJDLocalized.string(
                "controllers.disconnectSummary"
              )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 12)
        if device.sessionState == .suspended {
          Button(OJDLocalized.string("controllers.resume")) {
            Task { @MainActor in await viewModel.resumeController(device) }
          }
        } else {
          Button(
            OJDLocalized.string(
              "controllers.disconnectFromOJD"
            )
          ) { Task { @MainActor in await viewModel.suspendController(device) } }
        }
      }
    }

    private var controllerHeader: some View {
      HStack(alignment: .center, spacing: 10) {
        let presentation = device.publishedIdentityPresentation
        OJDSystemSymbol(
          name: presentation.controllerSymbolName,
          fallback: nil,
          fallbackSymbolName: presentation.controllerSymbolFallback
        ).font(.title).foregroundColor(presentation.glyphFamily.controllerSymbolColor)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(device.name).font(.headline.weight(.semibold)).lineLimit(1)
          Text("\(reportedValue(device.connection)) · " + device.publishedIdentityLabel)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 0)
      }
    }

    @ViewBuilder
    private var activeProfileRow: some View {
      switch activeProfile {
      case .loading:
        KeyValueRow(
          label: OJDLocalized.string("controllers.activeProfile"),
          value: OJDLocalized.string("status.checking")
        )
      case .noProfile:
        KeyValueRow(
          label: OJDLocalized.string("controllers.activeProfile"),
          value: OJDLocalized.string("common.none")
        )
      case .profile(let name):
        KeyValueRow(
          label: OJDLocalized.string("controllers.activeProfile"),
          value: name
        )
      case .unavailable(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "controllers.profileUnavailable"
          ),
          message: message
        )
      case .error(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "controllers.profileLoadError"
          ),
          message: message
        )
      }
    }

    private func profileFailureRow(label: String, message: String) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(OJDLocalized.string("controllers.activeProfile"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
          Spacer()
          Text(OJDLocalized.string("common.needsAttention"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }

        Text(label).font(.caption.weight(.semibold))
        Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        Button(OJDLocalized.string("common.tryAgain"), action: retry)

      }
    }

    @ViewBuilder
    private func controllerDetails(compact: Bool) -> some View {
      if compact {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(controllerFacts.enumerated()), id: \.offset) { _, fact in
            ControllerFactView(label: fact.label, value: fact.value)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          // Rows carry their facts by value: index-based rows crashed when a
          // later render had fewer facts than the ForEach identities it reused.
          let facts = controllerFacts
          let rows = stride(from: 0, to: facts.count, by: 2).map {
            Array(facts[$0..<min($0 + 2, facts.count)])
          }
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            HStack(alignment: .top, spacing: 24) {
              ForEach(Array(row.enumerated()), id: \.offset) { _, fact in
                ControllerFactView(label: fact.label, value: fact.value).frame(
                  maxWidth: .infinity,
                  alignment: .leading
                )
              }
              if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
            }
          }
        }
      }
    }

    private var controllerFacts: [(label: String, value: String)] {
      [
        (
          OJDLocalized.string("controllers.publishedAs"),
          device.publishedIdentityLabel
        ),
        (
          OJDLocalized.string("common.protocol"),
          device.protocolBinding.displayLabel
        ),
        (OJDLocalized.string("common.serialNumber"), serialNumberLabel),
        (OJDLocalized.string("controllers.battery"), batteryPercentageLabel),
        (
          OJDLocalized.string("controllers.chargingState"),
          chargingStateLabel
        ),
        (OJDLocalized.string("controllers.cableState"), cableStateLabel),
        (OJDLocalized.string("controllers.usbIdentifier"), usbIdentifier),
        (
          OJDLocalized.string("common.inputEndpoint"),
          endpointLabel(device.inputEndpoint)
        ),
        (
          OJDLocalized.string("common.outputEndpoint"),
          endpointLabel(device.outputEndpoint)
        ),
      ]
    }

    var serialNumberLabel: String {
      guard let serialNumber = device.serialNumber else {
        return OJDLocalized.string("controllers.notReported")
      }
      return reportedValue(serialNumber)
    }

    var usbIdentifier: String {
      guard device.vendorID != 0 || device.productID != 0 else {
        return OJDLocalized.string("controllers.notReported")
      }
      return String(format: "%04X:%04X", device.vendorID, device.productID)
    }

    var batteryPercentageLabel: String {
      guard let percentage = device.connectionState?.power.battery.percentageText else {
        return OJDLocalized.string("common.unknown")
      }
      return percentage
    }

    var chargingStateLabel: String {
      switch device.connectionState?.power.charging ?? .unknown {
      case .discharging:
        return OJDLocalized.string("controllers.discharging")
      case .charging: return OJDLocalized.string("controllers.charging")
      case .full: return OJDLocalized.string("controllers.batteryFull")
      case .notChargeable:
        return OJDLocalized.string("controllers.notChargeable")
      case .unknown: return OJDLocalized.string("common.unknown")
      }
    }

    var cableStateLabel: String {
      switch device.connectionState?.power.wiredPower {
      case true?:
        return OJDLocalized.string("settings.controllerConnectedShort")
      case false?:
        return OJDLocalized.string("settings.controllerDisconnectedShort")
      case nil: return OJDLocalized.string("common.unknown")
      }
    }

    func reportedValue(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? OJDLocalized.string("controllers.notReported") : trimmed
    }

    func endpointLabel(_ endpoint: UInt8) -> String {
      endpoint == 0
        ? OJDLocalized.string("controllers.notReported")
        : String(format: "0x%02X", endpoint)
    }
  }

#endif
