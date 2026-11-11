#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Raw Packet Capture section of the developer tools: the capture state, the packet filter,
  /// the Start, Stop, Clear, Copy All and Export buttons, and the packet table.
  struct DeveloperPacketCaptureView: View {
    /// The state of the developer tools.
    @ObservedObject
    var model: DeveloperToolsViewModel

    /// The Packet capture section: the status, the filter, the capture buttons, the packets and a
    /// sharing warning.
    var body: some View {
      let displayedPackets = model.displayedPackets
      Section(OJDLocalized.string("ui.developer.packetCapture")) {
        captureStatus
        Picker(OJDLocalized.string("ui.developer.packetCapture"), selection: $model.packetFilter) {
          Text(OJDLocalized.string("ui.developer.packetFilterActivity")).tag(
            DeveloperToolsViewModel.PacketFilter.activity
          )
          Text(OJDLocalized.string("ui.developer.packetFilterAll")).tag(
            DeveloperToolsViewModel.PacketFilter.all
          )
        }.pickerStyle(.segmented).labelsHidden()
        HStack(spacing: OJDSpacing.small) {
          if model.isCapturing {
            Button(OJDLocalized.string("action.stop"), action: model.stopCapture)
          } else {
            Button(OJDLocalized.string("ui.developer.startCapture"), action: model.startCapture)
              .disabled(model.selectedDevice == nil)
          }
          Button(OJDLocalized.string("action.clear"), action: model.clearCapture)
            .disabled(model.packets.isEmpty && model.observedExtraInputs.isEmpty)
          Spacer(minLength: 12)
          Button(OJDLocalized.string("action.copyAll"), action: model.copyPacketCapture)
            .disabled(model.packets.isEmpty)
          Button(OJDLocalized.string("action.export"), action: model.exportPacketCapture)
            .disabled(model.packets.isEmpty)
        }
        if let exportError = model.exportError {
          Text(exportError).foregroundColor(Color(NSColor.systemOrange)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        packetList(displayedPackets)
        if model.hiddenIdlePacketCount > 0 {
          Text(
            OJDLocalized.plural("ui.developer.hiddenIdlePackets", model.hiddenIdlePacketCount)
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Text(OJDLocalized.string("ui.developer.packetSharingWarning")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor))
      }
    }

    /// The label of the capture state.
    @ViewBuilder
    private var captureStatus: some View {
      switch model.captureState {
      case .idle:
        statusLabel(OJDLocalized.string("ui.developer.ready"), symbol: "circle")
      case .starting:
        statusLabel(
          OJDLocalized.string("ui.developer.starting"),
          symbol: "clock"
        )
      case .capturing:
        statusLabel(
          OJDLocalized.string("ui.developer.capturing"),
          symbol: "record.circle"
        )
      case .stopped:
        statusLabel(
          OJDLocalized.plural(
            "ui.developer.stoppedPackets",
            model.displayedPackets.count
          ),
          symbol: "stop.circle"
        )
      case .noPackets:
        statusLabel(
          OJDLocalized.string("ui.developer.noPackets"),
          symbol: "tray"
        )
      case .failed(let message):
        statusLabel(message, symbol: SemanticState.failure.presentation.symbolName).foregroundColor(
          Color(SemanticState.failure.presentation.tone.color)
        )
      }
    }

    /// Returns the packet table, or a note that no packet has arrived.
    @ViewBuilder
    private func packetList(_ packets: [PacketLogEntry]) -> some View {
      if packets.isEmpty {
        Text(
          model.isCapturing
            ? OJDLocalized.string("ui.developer.waitingForPackets")
            : OJDLocalized.string("ui.developer.emptyCapture")
        ).foregroundColor(Color(NSColor.secondaryLabelColor))
        if model.isCapturing {
          Text(OJDLocalized.string("ui.developer.keepAliveNote")).font(.caption).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
      } else {
        DeveloperPacketTable(packets: packets).frame(minHeight: 160, maxHeight: 240)
      }
    }

    /// Returns a label with the SF Symbol `symbol` and `text`, read by VoiceOver as one element.
    private func statusLabel(_ text: String, symbol: String) -> some View {
      HStack(spacing: OJDSpacing.small) {
        OJDSystemSymbol(
          name: symbol,
          fallback: OJDLocalized.string("term.status")
        ).accessibilityHidden(true)
        Text(text)
      }.accessibilityElement(children: .combine)
    }
  }

  /// The table of packets: each packet's time since the first one, direction, length and bytes.
  private struct DeveloperPacketTable: NSViewRepresentable {
    /// The packets to list.
    let packets: [PacketLogEntry]

    /// Creates the data source and delegate of the table.
    ///
    /// - Returns: The coordinator.
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Creates the scroll view that holds the table with its time, direction, bytes and data
    /// columns.
    ///
    /// - Parameter context: The context of the representable, whose coordinator supplies the rows.
    /// - Returns: The scroll view.
    func makeNSView(context: Context) -> NSScrollView {
      let table = NSTableView()
      table.headerView = NSTableHeaderView()
      table.usesAlternatingRowBackgroundColors = true
      table.rowHeight = 20
      table.delegate = context.coordinator
      table.dataSource = context.coordinator
      table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
      for (identifier, title, width) in [
        ("time", OJDLocalized.string("ui.developer.packetColumnTime"), 80.0),
        ("direction", OJDLocalized.string("ui.developer.packetColumnDirection"), 90.0),
        ("bytes", OJDLocalized.string("ui.developer.packetColumnBytes"), 60.0),
        ("data", OJDLocalized.string("ui.developer.packetColumnData"), 300.0),
      ] {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = width
        table.addTableColumn(column)
      }
      let scrollView = NSScrollView()
      scrollView.documentView = table
      scrollView.hasVerticalScroller = true
      scrollView.hasHorizontalScroller = true
      scrollView.autohidesScrollers = true
      scrollView.borderType = .bezelBorder
      scrollView.setAccessibilityLabel(
        OJDLocalized.string("ui.developer.packetCapture")
      )
      return scrollView
    }

    /// Gives the table the packets and reloads it.
    ///
    /// - Parameters:
    ///   - scrollView: The scroll view that holds the table.
    ///   - context: The context of the representable, whose coordinator supplies the rows.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      context.coordinator.packets = packets
      (scrollView.documentView as? NSTableView)?.reloadData()
    }

    /// Supplies the rows of the packet table.
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
      /// The packets to list.
      var packets: [PacketLogEntry] = []

      /// Returns the number of packets.
      ///
      /// - Parameter tableView: The packet table.
      /// - Returns: The number of packets.
      func numberOfRows(in tableView: NSTableView) -> Int { packets.count }

      /// Returns the cell that shows one field of a packet.
      ///
      /// The column picks the field: the time since the first packet, the direction, the length or
      /// the bytes.
      ///
      /// - Parameters:
      ///   - tableView: The packet table.
      ///   - tableColumn: The column of the cell.
      ///   - row: The index of the packet.
      /// - Returns: The cell.
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
        switch tableColumn?.identifier.rawValue {
        case "time":
          textField.stringValue = String(format: "+%.3fs", packet.timestamp - firstTimestamp)
        case "direction": textField.stringValue = packet.direction.rawValue.uppercased()
        case "bytes": textField.stringValue = String(packet.length)
        default: textField.stringValue = packet.hex
        }
        return cell
      }
    }
  }

#endif
