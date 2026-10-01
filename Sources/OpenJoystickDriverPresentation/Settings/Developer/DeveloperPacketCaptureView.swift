#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperPacketCaptureView: View {
    @ObservedObject
    var model: DeveloperToolsViewModel

    var body: some View {
      let displayedPackets = model.displayedPackets
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            captureStatus
            Picker("", selection: $model.packetFilter) {
              Text(OJDLocalized.string("developer.packetFilterActivity", fallback: "Activity")).tag(
                DeveloperToolsViewModel.PacketFilter.activity
              )
              Text(OJDLocalized.string("developer.packetFilterAll", fallback: "All")).tag(
                DeveloperToolsViewModel.PacketFilter.all
              )
            }.pickerStyle(SegmentedPickerStyle()).frame(width: 150).labelsHidden()
            Spacer()
            if model.isCapturing {
              Button(
                OJDLocalized.string("common.stop", fallback: "Stop"),
                action: model.stopCapture
              ).keyboardShortcut(.defaultAction)
            } else {
              Button(
                OJDLocalized.string("developer.startCapture", fallback: "Start Capture"),
                action: model.startCapture
              ).keyboardShortcut(.defaultAction).disabled(model.selectedDevice == nil)
            }
            Button(
              OJDLocalized.string("common.clear", fallback: "Clear"),
              action: model.clearCapture
            ).disabled(model.packets.isEmpty && model.observedExtraInputs.isEmpty)
            OJDCompactSymbolButton(
              symbolName: "doc.on.doc",
              label: OJDLocalized.string("common.copyAll", fallback: "Copy All"),
              action: model.copyPacketCapture
            ).disabled(model.packets.isEmpty)
            OJDCompactSymbolButton(
              symbolName: "square.and.arrow.up",
              label: OJDLocalized.string("common.export", fallback: "Export..."),
              action: model.exportPacketCapture
            ).disabled(model.packets.isEmpty)
          }

          packetList(displayedPackets)

          if model.hiddenIdlePacketCount > 0 {
            Text(
              OJDLocalized.formatted(
                "developer.hiddenIdlePackets",
                fallback: "Hidden %d idle packets (still included in Export).",
                model.hiddenIdlePacketCount
              )
            ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          }

          Text(
            OJDLocalized.string(
              "developer.packetSharingWarning",
              fallback: "Packet contents vary by controller. Check the file before sharing."
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("developer.packetCapture", fallback: "Raw Packet Capture")).font(
          .headline
        )
      }
    }

    @ViewBuilder
    private var captureStatus: some View {
      switch model.captureState {
      case .idle:
        statusLabel(OJDLocalized.string("developer.ready", fallback: "Ready"), symbol: "circle")
      case .starting:
        statusLabel(
          OJDLocalized.string("developer.starting", fallback: "Starting..."),
          symbol: "clock"
        )
      case .capturing:
        statusLabel(
          OJDLocalized.string("developer.capturing", fallback: "Capturing"),
          symbol: "record.circle"
        )
      case .stopped:
        statusLabel(
          OJDLocalized.formatted(
            "developer.stoppedPackets",
            fallback: "Stopped · %d packets",
            model.displayedPackets.count
          ),
          symbol: "stop.circle"
        )
      case .noPackets:
        statusLabel(
          OJDLocalized.string("developer.noPackets", fallback: "No packets captured"),
          symbol: "tray"
        )
      case .failed(let message):
        statusLabel(message, symbol: SemanticState.failure.presentation.symbolName).foregroundColor(
          Color(SemanticState.failure.presentation.tone.color)
        )
      }
    }

    @ViewBuilder
    private func packetList(_ packets: [PacketLogEntry]) -> some View {
      if packets.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            model.isCapturing
              ? OJDLocalized.string(
                "developer.waitingForPackets",
                fallback: "Waiting for USB packets. Press a controller button."
              )
              : OJDLocalized.string(
                "developer.emptyCapture",
                fallback: "Press Start Capture, then press controller buttons."
              )
          ).foregroundColor(Color(NSColor.secondaryLabelColor))
          if model.isCapturing {
            Text(
              OJDLocalized.string(
                "developer.keepAliveNote",
                fallback: "Routine idle traffic is hidden so controller activity stays visible."
              )
            ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        }.padding(10).frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
      } else {
        DeveloperPacketTable(packets: packets).frame(minHeight: 160, maxHeight: 240)
      }
    }

    private func statusLabel(_ text: String, symbol: String) -> some View {
      HStack(spacing: 6) {
        OJDSystemSymbol(
          name: symbol,
          fallback: OJDLocalized.string("common.status", fallback: "Status")
        )
        Text(text)
      }.accessibilityElement(children: .combine)
    }
  }

  private struct DeveloperPacketTable: NSViewRepresentable {
    let packets: [PacketLogEntry]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
      let table = NSTableView()
      table.headerView = NSTableHeaderView()
      table.usesAlternatingRowBackgroundColors = true
      table.rowHeight = 20
      table.delegate = context.coordinator
      table.dataSource = context.coordinator
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("packet"))
      column.title = OJDLocalized.string(
        "developer.packetColumns",
        fallback: "Time       Direction  Bytes  Data"
      )
      column.minWidth = 480
      table.addTableColumn(column)
      let scrollView = NSScrollView()
      scrollView.documentView = table
      scrollView.hasVerticalScroller = true
      scrollView.hasHorizontalScroller = true
      scrollView.autohidesScrollers = true
      scrollView.borderType = .bezelBorder
      scrollView.setAccessibilityLabel(
        OJDLocalized.string("developer.packetCapture", fallback: "Raw Packet Capture")
      )
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      context.coordinator.packets = packets
      (scrollView.documentView as? NSTableView)?.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
      var packets: [PacketLogEntry] = []

      func numberOfRows(in tableView: NSTableView) -> Int { packets.count }

      func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
      ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("packet-cell")
        let cell =
          (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
          ?? NSTableCellView()
        cell.identifier = identifier
        let textField: NSTextField
        if let existing = cell.textField {
          textField = existing
        } else {
          textField = NSTextField(labelWithString: "")
          textField.translatesAutoresizingMaskIntoConstraints = false
          textField.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
          )
          textField.lineBreakMode = .byClipping
          cell.addSubview(textField)
          cell.textField = textField
          NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
          ])
        }
        let packet = packets[row]
        let firstTimestamp = packets.first?.timestamp ?? packet.timestamp
        let direction = packet.direction.rawValue.uppercased().padding(
          toLength: 9,
          withPad: " ",
          startingAt: 0
        )
        textField.stringValue = String(
          format: "+%7.3fs  %@  %5d  %@",
          packet.timestamp - firstTimestamp,
          direction,
          packet.length,
          packet.hex
        )
        return cell
      }
    }
  }

#endif
