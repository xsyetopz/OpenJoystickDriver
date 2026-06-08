import OpenJoystickDriverKit
import SwiftUI

private actor InputTestSampler {
  private let client = XPCClient()

  init() {
    client.connect()
  }

  func disconnect() {
    client.disconnect()
  }

  func deviceInputState(vendorID: UInt16, productID: UInt16) async -> DeviceInputState? {
    try? await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(vendorID: UInt16, productID: UInt16) async -> [PacketLogEntry] {
    (try? await client.packetLog(vendorID: vendorID, productID: productID)) ?? []
  }
}

struct InputTestWindowView: View {
  private let inputRefreshIntervalNanoseconds: UInt64 = 8_333_333
  private let packetLogRefreshIntervalNanoseconds: UInt64 = 1_000_000_000

  @EnvironmentObject var model: AppModel
  @State private var selectedDeviceID: String?
  @State private var state: DeviceInputState?
  @State private var packetLog: [PacketLogEntry] = []
  @State private var rumbleRunning = false
  @State private var rumbleResult: String?
  @State private var rumbleLeft = 180.0
  @State private var rumbleRight = 180.0
  @State private var rumbleLT = 0.0
  @State private var rumbleRT = 0.0
  @State private var rumbleDurationMs = 450.0
  @State private var showPackets = false
  @State private var stateTask: Task<Void, Never>?
  @State private var packetLogTask: Task<Void, Never>?
  @State private var sampler = InputTestSampler()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        if let device = selectedDevice {
          VStack(alignment: .leading, spacing: 14) {
            controllerHero(device)
            HStack(alignment: .top, spacing: 16) {
              OJDCard(title: "Live input") {
                axesGrid
                Divider()
                buttonGrid
              }
              .frame(width: 350, alignment: .topLeading)

              VStack(alignment: .leading, spacing: 12) {
                outputTestRow(device)
                packetLogToggle
                if showPackets {
                  packetLogView
                }
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
          }
        } else {
          OJDCard {
            VStack(spacing: 10) {
              StatusOrb(isReady: false, isBusy: false)
              Text("No controller selected").font(.headline)
              Text("Connect a controller, then refresh.")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
          }
        }
      }
      .padding(18)
    }
    .frame(minWidth: 860, minHeight: 560)
    .onAppear {
      selectedDeviceID = selectedDeviceID ?? model.devices.first?.id
      startRefreshTasks()
    }
    .onDisappear {
      stateTask?.cancel()
      packetLogTask?.cancel()
      stateTask = nil
      packetLogTask = nil
      Task { await sampler.disconnect() }
    }
  }

  private var selectedDevice: DeviceViewModel? {
    if let selectedDeviceID, let selected = model.devices.first(where: { $0.id == selectedDeviceID }) {
      return selected
    }
    return model.devices.first
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Input Test")
          .font(.system(size: 24, weight: .semibold))
        Text("Live input, packet log, and rumble controls.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      HStack(spacing: 8) {
        Text("Controller")
          .font(.caption.weight(.semibold))
          .foregroundColor(.secondary)
        Picker("", selection: Binding(get: {
          selectedDevice?.id ?? ""
        }, set: { value in
          selectedDeviceID = value
        })) {
          ForEach(model.devices) { device in
            Text(device.name).tag(device.id)
          }
        }
        .labelsHidden()
        .frame(width: 260)
        .disabled(model.devices.isEmpty)
        SwiftUI.Button("Refresh") {
          Task {
            await model.syncFromDaemonNow()
            await refreshState()
            await refreshPacketLog()
          }
        }
        .controlSize(.small)
      }
    }
  }

  private func controllerHero(_ device: DeviceViewModel) -> some View {
    OJDCard {
      HStack(alignment: .center, spacing: 14) {
        StatusOrb(isReady: state != nil, isBusy: false)
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 8) {
            Text(device.name)
              .font(.system(size: 19, weight: .semibold))
              .lineLimit(1)
            Text(state == nil ? "idle" : "live")
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(state == nil ? .secondary : .green)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(
                Capsule().fill((state == nil ? Color.secondary : Color.green).opacity(0.12))
              )
          }
          HStack(spacing: 7) {
            MiniBadge(device.parser)
            MiniBadge(device.connection)
            MiniBadge(String(format: "%04X:%04X", device.vendorID, device.productID))
            if let serial = device.serialNumber, !serial.isEmpty {
              MiniBadge("Serial \(serial)")
                .layoutPriority(-1)
            }
          }
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text(state == nil ? "Waiting for input" : "Reading input")
            .font(.caption.weight(.semibold))
          Text(buttonSummary)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  private var axesGrid: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Sticks and triggers").font(.caption.weight(.semibold))
        Spacer()
        Text(state == nil ? "idle" : "live")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(state == nil ? .secondary : .green)
      }
      HStack(spacing: 12) {
        AxisMeter(label: "Left X", value: state?.leftStickX ?? 0, range: -1...1)
        AxisMeter(label: "Left Y", value: state?.leftStickY ?? 0, range: -1...1)
      }
      HStack(spacing: 12) {
        AxisMeter(label: "Right X", value: state?.rightStickX ?? 0, range: -1...1)
        AxisMeter(label: "Right Y", value: state?.rightStickY ?? 0, range: -1...1)
      }
      HStack(spacing: 12) {
        AxisMeter(label: "LT", value: state?.leftTrigger ?? 0, range: 0...1)
        AxisMeter(label: "RT", value: state?.rightTrigger ?? 0, range: 0...1)
      }
    }
  }

  private var buttonGrid: some View {
    let pressed = Set(state?.pressedButtons ?? [])
    let buttons = supportedButtons(for: selectedDevice?.parser)
    let columnCount = 6
    let rowCount = (buttons.count + columnCount - 1) / columnCount
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Buttons").font(.caption.weight(.semibold))
        Spacer()
        Text(pressed.isEmpty ? "none pressed" : "\(pressed.count) pressed")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(pressed.isEmpty ? .secondary : .accentColor)
      }
      VStack(alignment: .leading, spacing: 6) {
        ForEach(0..<rowCount, id: \.self) { row in
          HStack(spacing: 6) {
            ForEach(0..<columnCount, id: \.self) { column in
              let index = row * columnCount + column
              if index < buttons.count {
                let button = buttons[index]
                buttonPill(button: button, isDown: pressed.contains(button.rawValue))
              }
            }
          }
        }
      }
    }
    .transaction { transaction in
      transaction.animation = nil
    }
  }

  private var buttonSummary: String {
    let pressed = state?.pressedButtons ?? []
    if pressed.isEmpty {
      return "No buttons pressed"
    }
    return "\(pressed.count) button\(pressed.count == 1 ? "" : "s") pressed"
  }

  @ViewBuilder
  private func buttonPill(button: OpenJoystickDriverKit.Button, isDown: Bool) -> some View {
    if #available(macOS 11.0, *) {
      Image(systemName: button.systemImageName)
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 32, height: 30)
        .background(isDown ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.14))
        .foregroundColor(isDown ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transaction { transaction in
          transaction.animation = nil
        }
        .accessibilityLabel(Text(button.displayName))
    } else {
      Text(button.displayName)
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: 32, height: 30)
        .background(isDown ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.14))
        .foregroundColor(isDown ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transaction { transaction in
          transaction.animation = nil
        }
    }
  }

  private func supportedButtons(for parser: String?) -> [OpenJoystickDriverKit.Button] {
    switch parser {
    case "DS4":
      return [
        .cross, .circle, .square, .triangle,
        .l1, .r1, .leftStick, .rightStick,
        .share, .options, .ps, .touchpad,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    case "GIP":
      return [
        .a, .b, .x, .y,
        .leftBumper, .rightBumper,
        .leftStick, .rightStick,
        .back, .start, .guide, .share,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    case "Xbox360":
      return [
        .a, .b, .x, .y,
        .leftBumper, .rightBumper,
        .leftStick, .rightStick,
        .back, .start, .guide,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    default:
      return [
        .genericButton1, .genericButton2, .genericButton3, .genericButton4,
        .genericButton5, .genericButton6, .genericButton7, .genericButton8,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
      ]
    }
  }

  private func outputTestRow(_ device: DeviceViewModel) -> some View {
    let canRumble = device.supportsPhysicalRumble
    return OJDCard(title: "Rumble test") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(
            canRumble
              ? "Send a short rumble command to the controller."
              : "This controller does not expose rumble."
          )
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Text(canRumble ? "supported" : "unavailable")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(canRumble ? .green : .secondary)
        }
        VStack(alignment: .leading, spacing: 7) {
          Text("Motors")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
          HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
              RumbleSlider(label: "Left", value: $rumbleLeft)
              RumbleSlider(label: "Right", value: $rumbleRight)
            }
            VStack(alignment: .leading, spacing: 5) {
              RumbleSlider(label: "LT", value: $rumbleLT)
              RumbleSlider(label: "RT", value: $rumbleRT)
            }
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            rumbleIconButton(
              rumbleRunning ? "Sending" : "Pulse",
              systemName: rumbleRunning ? "hourglass" : "dot.radiowaves.left.and.right"
            ) {
              sendRumble(to: device, durationMs: Int(rumbleDurationMs))
            }
            .disabled(rumbleRunning || !canRumble)
            rumbleIconButton("Hold", systemName: "infinity") {
              sendRumble(to: device, durationMs: 0)
            }
            .disabled(!canRumble)
            rumbleIconButton("Stop", systemName: "stop.fill") {
              sendRumble(to: device, left: 0, right: 0, lt: 0, rt: 0, durationMs: 0)
            }
            .disabled(!canRumble)
            Divider().frame(height: 18)
            Stepper(
              "Duration \(Int(rumbleDurationMs)) ms",
              value: $rumbleDurationMs,
              in: 50...5000,
              step: 50
            )
              .font(.caption)
              .frame(width: 160)
          }
          HStack(spacing: 8) {
            rumbleIconButton("Left motor", systemName: "l.circle") {
              sendRumble(
                to: device,
                left: UInt8(clamping: Int(rumbleLeft)),
                right: 0,
                lt: 0,
                rt: 0
              )
            }
            .disabled(rumbleRunning || !canRumble)
            rumbleIconButton("Right motor", systemName: "r.circle") {
              sendRumble(
                to: device,
                left: 0,
                right: UInt8(clamping: Int(rumbleRight)),
                lt: 0,
                rt: 0
              )
            }
            .disabled(rumbleRunning || !canRumble)
            Divider().frame(height: 16)
            rumbleIconButton("Low", systemName: "speaker.wave.1.fill") {
              setRumbleValues(left: 32, right: 32, lt: 32, rt: 32)
            }
            rumbleIconButton("Mid", systemName: "speaker.wave.2.fill") {
              setRumbleValues(left: 128, right: 128, lt: 128, rt: 128)
            }
            rumbleIconButton("Max", systemName: "speaker.wave.3.fill") {
              setRumbleValues(left: 255, right: 255, lt: 255, rt: 255)
            }
            rumbleIconButton("Zero", systemName: "speaker.slash.fill") {
              setRumbleValues(left: 0, right: 0, lt: 0, rt: 0)
            }
          }
          HStack(spacing: 8) {
            if let rumbleResult {
              Text("Last command: \(rumbleResult)").font(.caption).foregroundColor(.secondary)
            } else {
              Text("Rumble commands affect the physical controller only.")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func rumbleIconButton(
    _ title: String,
    systemName: String,
    action: @escaping () -> Void
  ) -> some View {
    SwiftUI.Button(action: action) {
      if #available(macOS 11.0, *) {
        VStack(spacing: 3) {
          Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
          Text(rumbleGlyphCaption(title))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
        }
        .frame(width: 44, height: 36)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
      } else {
        Text(title)
          .font(.caption)
          .frame(width: 44, height: 36)
      }
    }
    .buttonStyle(.borderless)
  }

  private func rumbleGlyphCaption(_ title: String) -> String {
    switch title {
    case "Sending": return "sending"
    case "Pulse": return "pulse"
    case "Hold": return "hold"
    case "Stop": return "stop"
    case "Left motor": return "L"
    case "Right motor": return "R"
    case "Low": return "low"
    case "Mid": return "mid"
    case "Max": return "max"
    case "Zero": return "zero"
    default: return title
    }
  }

  private func sendRumble(
    to device: DeviceViewModel,
    left: UInt8? = nil,
    right: UInt8? = nil,
    lt: UInt8? = nil,
    rt: UInt8? = nil,
    durationMs: Int? = nil
  ) {
    rumbleRunning = true
    rumbleResult = nil
    Task {
      let ok = await model.sendPhysicalRumble(
        vendorID: device.vendorID,
        productID: device.productID,
        left: left ?? UInt8(clamping: Int(rumbleLeft)),
        right: right ?? UInt8(clamping: Int(rumbleRight)),
        lt: lt ?? UInt8(clamping: Int(rumbleLT)),
        rt: rt ?? UInt8(clamping: Int(rumbleRT)),
        durationMs: durationMs ?? Int(rumbleDurationMs)
      )
      rumbleResult = ok ? "sent" : "not available"
      rumbleRunning = false
    }
  }

  private func setRumbleValues(left: Double, right: Double, lt: Double, rt: Double) {
    rumbleLeft = left
    rumbleRight = right
    rumbleLT = lt
    rumbleRT = rt
  }

  private var packetLogView: some View {
    OJDCard(title: "Recent packets") {
      VStack(alignment: .leading, spacing: 8) {
        if packetLog.isEmpty {
          Text("No packets captured yet.").font(.caption).foregroundColor(.secondary)
        } else {
          ForEach(Array(packetLog.suffix(8).enumerated()), id: \.offset) { _, entry in
            Text("\(entry.direction) \(entry.length)b \(entry.hex)")
              .font(.system(.caption, design: .monospaced))
              .lineLimit(1)
              .padding(.vertical, 1)
          }
        }
      }
    }
  }

  private var packetLogToggle: some View {
    SwiftUI.Button {
      showPackets.toggle()
    } label: {
      HStack {
        Text(showPackets ? "Hide packet log" : "Show packet log")
        Spacer()
        if #available(macOS 11.0, *) {
          Image(systemName: showPackets ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .semibold))
        } else {
          Text(showPackets ? "▴" : "▾")
        }
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

  private func startRefreshTasks() {
    if stateTask == nil {
      stateTask = Task {
        while !Task.isCancelled {
          await refreshState()
          try? await Task.sleep(nanoseconds: inputRefreshIntervalNanoseconds)
        }
      }
    }
    if packetLogTask == nil {
      packetLogTask = Task {
        await refreshPacketLog()
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: packetLogRefreshIntervalNanoseconds)
          await refreshPacketLog()
        }
      }
    }
  }

  private func refreshState() async {
    guard let device = selectedDevice else {
      state = nil
      return
    }
    let nextState = await sampler.deviceInputState(
      vendorID: device.vendorID,
      productID: device.productID
    )
    if state != nextState {
      state = nextState
    }
  }

  private func refreshPacketLog() async {
    guard let device = selectedDevice else {
      packetLog = []
      return
    }
    packetLog = await sampler.packetLog(vendorID: device.vendorID, productID: device.productID)
  }
}

private struct RumbleSlider: View {
  let label: String
  @Binding var value: Double

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .frame(width: 34, alignment: .leading)
      Slider(value: $value, in: 0...255, step: 1)
        .frame(width: 116)
      Text("\(Int(value))")
        .font(.system(.caption, design: .monospaced))
        .frame(width: 30, alignment: .trailing)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct AxisMeter: View {
  let label: String
  let value: Float
  let range: ClosedRange<Float>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label).font(.caption.weight(.semibold))
        Spacer()
        Text(String(format: "%.3f", value))
          .font(.system(.caption, design: .monospaced))
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.18))
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor)
            .frame(width: max(4, proxy.size.width * normalizedValue))
        }
      }
      .frame(width: 140, height: 7)
      .transaction { transaction in
        transaction.animation = nil
      }
    }
  }

  private var normalizedValue: CGFloat {
    let width = range.upperBound - range.lowerBound
    guard width > 0 else { return 0.0 }
    let normalized = (value - range.lowerBound) / width
    return CGFloat(max(0, min(1, normalized)))
  }
}
