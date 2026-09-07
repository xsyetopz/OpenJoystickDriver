import Foundation

/// Original Xbox XID input report length used by Linux `xpad_process_packet`.
private let xidInputReportLength = 20
private let xidTriggerMax: Float = 255
private let xidStickMax = Float(Int16.max)

/// Parser for original Xbox XID pads (`xpad` `XTYPE_XBOX`).
///
/// XID is vendor USB, not HID. Layout follows Linux `xpad_process_packet`:
/// digital dpad/start/back/sticks in byte 2, analog A/B/X/Y in bytes 4–7,
/// analog black/white shoulders in bytes 8–9, analog triggers in bytes 10–11,
/// and Int16 LE sticks at bytes 12–19. Any nonzero analog face or shoulder
/// value is pressed, matching `input_report_key` in `xpad.c`.
public final class XIDParser: InputParser, @unchecked Sendable {
  private var prevDigital: UInt8 = 0
  private var prevA: UInt8 = 0
  private var prevB: UInt8 = 0
  private var prevX: UInt8 = 0
  private var prevY: UInt8 = 0
  private var prevBlack: UInt8 = 0
  private var prevWhite: UInt8 = 0
  private var prevLT: UInt8 = 0
  private var prevRT: UInt8 = 0
  private var prevLSX: Int16 = 0
  private var prevLSY: Int16 = 0
  private var prevRSX: Int16 = 0
  private var prevRSY: Int16 = 0

  public init() {}

  public func performHandshake(handle: (any USBTransportSession)?) async throws {
    await Task.yield()
  }

  public func parse(data: Data) throws -> [ControllerEvent] {
    guard data.count >= xidInputReportLength else { return [] }
    let bytes = Array(data)
    let digital = bytes[2]
    let analogA = bytes[4]
    let analogB = bytes[5]
    let analogX = bytes[6]
    let analogY = bytes[7]
    let black = bytes[8]
    let white = bytes[9]
    let lt = bytes[10]
    let rt = bytes[11]
    let lsx = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[14]) | (UInt16(bytes[15]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[16]) | (UInt16(bytes[17]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[18]) | (UInt16(bytes[19]) << 8))

    var events: [ControllerEvent] = []
    events += parseDigital(curr: digital)
    events += parseAnalogKey(prev: prevA, curr: analogA, button: .a)
    events += parseAnalogKey(prev: prevB, curr: analogB, button: .b)
    events += parseAnalogKey(prev: prevX, curr: analogX, button: .x)
    events += parseAnalogKey(prev: prevY, curr: analogY, button: .y)
    events += parseAnalogKey(prev: prevBlack, curr: black, button: .leftBumper)
    events += parseAnalogKey(prev: prevWhite, curr: white, button: .rightBumper)
    if lt != prevLT { events.append(.leftTriggerChanged(Float(lt) / xidTriggerMax)) }
    if rt != prevRT { events.append(.rightTriggerChanged(Float(rt) / xidTriggerMax)) }
    if lsx != prevLSX || lsy != prevLSY {
      events.append(.leftStickChanged(x: normalizeStick(lsx), y: -normalizeStick(lsy)))
    }
    if rsx != prevRSX || rsy != prevRSY {
      events.append(.rightStickChanged(x: normalizeStick(rsx), y: -normalizeStick(rsy)))
    }

    prevDigital = digital
    prevA = analogA
    prevB = analogB
    prevX = analogX
    prevY = analogY
    prevBlack = black
    prevWhite = white
    prevLT = lt
    prevRT = rt
    prevLSX = lsx
    prevLSY = lsy
    prevRSX = rsx
    prevRSY = rsy
    return events
  }

  private func parseDigital(curr: UInt8) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let changed = curr ^ prevDigital
    func check(_ bit: Int, _ button: Button) {
      let mask = UInt8(1 << bit)
      guard changed & mask != 0 else { return }
      events.append((curr & mask) != 0 ? .buttonPressed(button) : .buttonReleased(button))
    }
    let dpadMask: UInt8 = 0x0F
    if (curr & dpadMask) != (prevDigital & dpadMask) {
      events.append(.dpadChanged(mapDpad(curr & dpadMask)))
    }
    check(4, .start)
    check(5, .back)
    check(6, .leftStick)
    check(7, .rightStick)
    return events
  }

  private func parseAnalogKey(prev: UInt8, curr: UInt8, button: Button) -> [ControllerEvent] {
    let wasPressed = prev != 0
    let isPressed = curr != 0
    guard wasPressed != isPressed else { return [] }
    return [isPressed ? .buttonPressed(button) : .buttonReleased(button)]
  }

  private func normalizeStick(_ raw: Int16) -> Float {
    if raw == Int16.min { return -1.0 }
    return Float(raw) / xidStickMax
  }

  private func mapDpad(_ value: UInt8) -> DpadDirection {
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast
    case 3: .southEast
    case 6: .southWest
    case 5: .northWest
    default: .neutral
    }
  }
}
