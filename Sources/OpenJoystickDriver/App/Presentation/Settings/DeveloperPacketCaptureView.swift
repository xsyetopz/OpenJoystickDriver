#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperPacketCaptureView: View {
    @ObservedObject var model: DeveloperToolsViewModel

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            captureStatus
            Spacer()
            if model.isCapturing {
              Button(
                OJDLocalized.string("common.stop", fallback: "Stop"),
                action: model.stopCapture
              )
            } else {
              Button(
                OJDLocalized.string("developer.startCapture", fallback: "Start Capture"),
                action: model.startCapture
              ).disabled(model.selectedDevice == nil)
            }
            Button(
              OJDLocalized.string("common.clear", fallback: "Clear"),
              action: model.clearCapture
            ).disabled(model.packets.isEmpty && model.observedExtraInputs.isEmpty)
            Button(OJDLocalized.string("common.copyAll", fallback: "Copy All"), action: copyAll)
              .disabled(model.packets.isEmpty)
            Button(
              OJDLocalized.string("common.export", fallback: "Export…"),
              action: presentSavePanel
            ).disabled(model.packets.isEmpty)
          }

          packetList

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

    @ViewBuilder private var captureStatus: some View {
      switch model.captureState {
      case .idle: statusLabel("Ready", symbol: "circle")
      case .starting: statusLabel("Starting…", symbol: "clock")
      case .capturing: statusLabel("Capturing", symbol: "record.circle")
      case .stopped: statusLabel("Stopped · \(model.packets.count) packets", symbol: "stop.circle")
      case .noPackets: statusLabel("No packets captured", symbol: "tray")
      case .failed(let message):
        statusLabel(message, symbol: "exclamationmark.triangle").foregroundColor(
          Color(NSColor.systemRed)
        )
      }
    }

    @ViewBuilder private var packetList: some View {
      if model.packets.isEmpty {
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
                fallback: "Some controllers send idle packets slowly."
              )
            ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        }.padding(10).frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
      } else {
        GeometryReader { geometry in
          ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Time       Direction  Bytes  Data").font(
                .system(.caption, design: .monospaced).weight(.semibold)
              ).foregroundColor(Color(NSColor.secondaryLabelColor))
              ForEach(Array(model.packets.enumerated()), id: \.offset) { _, packet in
                Text(packetLine(packet)).font(.system(.caption, design: .monospaced)).fixedSize(
                  horizontal: true,
                  vertical: false
                ).textSelectionIfAvailable()
              }
            }.padding(10).frame(minWidth: geometry.size.width, alignment: .topLeading)
          }
        }.frame(minHeight: 160, maxHeight: 240).background(Color(NSColor.textBackgroundColor))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor)))
      }
    }

    private func packetLine(_ packet: PacketLogEntry) -> String {
      let firstTimestamp = model.packets.first?.timestamp ?? packet.timestamp
      let direction = packet.direction.uppercased().padding(
        toLength: 9,
        withPad: " ",
        startingAt: 0
      )
      return String(
        format: "+%7.3fs  %@  %5d  %@",
        packet.timestamp - firstTimestamp,
        direction,
        packet.length,
        packet.hex
      )
    }

    private func statusLabel(_ text: String, symbol: String) -> some View {
      HStack(spacing: 6) {
        OJDSystemSymbol(name: symbol, fallback: "Status")
        Text(text)
      }.accessibilityElement(children: .combine)
    }

    private func copyAll() {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      let rows = ["Time       Direction  Bytes  Data"] + model.packets.map(packetLine)
      pasteboard.setString(rows.joined(separator: "\n"), forType: .string)
    }

    private func presentSavePanel() {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string(
        "developer.exportCapture",
        fallback: "Export Packet Capture"
      )
      panel.nameFieldStringValue = model.defaultExportFilename
      panel.canCreateDirectories = true
      let model = model
      panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        do { try model.encodedPacketLog().write(to: url, options: .atomic) } catch {
          NSAlert(error: error).runModal()
        }
      }
    }
  }

#endif
