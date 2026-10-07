import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// Pinned parse transcripts; the rendering rules are on `DriverParseCharacterizationTests`.
extension DriverParseCharacterizationTests {
  /// HID-descriptor element values; raw reports are ignored.
  @Test
  func hidDescriptor() throws {
    let lines = try transcript(Subjects.hidDescriptor, Self.hidDescriptorSteps)
    #expect(
      lines == [
        "report [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn1 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn1-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn2 [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn2-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn3 [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn3-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn4 [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn4-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn5 [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn5-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn6 [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn6-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn7 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn7-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn8 [menu] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn8-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn9 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn9-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn10 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn10-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn11 [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn11-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn12 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "btn12-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "u30=0 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "u30=127 [] hat=neutral ls=-128,0 rs=0,0 lt=0 rt=0",
        "u30=128 [] hat=neutral ls=128,0 rs=0,0 lt=0 rt=0",
        "u30=255 [] hat=neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "u31=0 [] hat=neutral ls=32767,-32767 rs=0,0 lt=0 rt=0",
        "u31=127 [] hat=neutral ls=32767,-128 rs=0,0 lt=0 rt=0",
        "u31=128 [] hat=neutral ls=32767,128 rs=0,0 lt=0 rt=0",
        "u31=255 [] hat=neutral ls=32767,32767 rs=0,0 lt=0 rt=0",
        "u32=0 [] hat=neutral ls=32767,32767 rs=0,0 lt=0 rt=0",
        "u32=127 [] hat=neutral ls=32767,32767 rs=0,0 lt=32639 rt=0",
        "u32=128 [] hat=neutral ls=32767,32767 rs=0,0 lt=32896 rt=0",
        "u32=255 [] hat=neutral ls=32767,32767 rs=0,0 lt=65535 rt=0",
        "u33=0 [] hat=neutral ls=32767,32767 rs=-32767,0 lt=65535 rt=0",
        "u33=127 [] hat=neutral ls=32767,32767 rs=-128,0 lt=65535 rt=0",
        "u33=128 [] hat=neutral ls=32767,32767 rs=128,0 lt=65535 rt=0",
        "u33=255 [] hat=neutral ls=32767,32767 rs=32767,0 lt=65535 rt=0",
        "u34=0 [] hat=neutral ls=32767,32767 rs=32767,-32767 lt=65535 rt=0",
        "u34=127 [] hat=neutral ls=32767,32767 rs=32767,-128 lt=65535 rt=0",
        "u34=128 [] hat=neutral ls=32767,32767 rs=32767,128 lt=65535 rt=0",
        "u34=255 [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=0",
        "u35=0 [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=0",
        "u35=127 [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=32639",
        "u35=128 [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=32896",
        "u35=255 [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h0 [] hat=north ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h1 [] hat=northEast ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h2 [] hat=east ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h3 [] hat=southEast ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h4 [] hat=south ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h5 [] hat=southWest ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h6 [] hat=west ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h7 [] hat=northWest ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h8 [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "h15 [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "repeat [] hat=neutral ls=32767,32767 rs=32767,32767 lt=65535 rt=65535",
        "span0 [] hat=neutral ls=0,32767 rs=32767,32767 lt=65535 rt=65535",
        "accel [] hat=neutral ls=0,32767 rs=32767,32767 lt=65535 rt=65535",
        "page7 [] hat=neutral ls=0,32767 rs=32767,32767 lt=65535 rt=65535",
      ]
    )
  }

  /// Captured G7 SE status frames around a synthetic input frame.
  @Test
  func capturedG7SE() throws {
    let lines = transcript(
      try Self.captured(0x3537, 0x1010),
      labels: .standard,
      Self.gipCapturedSteps(Self.capturedG7SEStatus)
    )
    #expect(
      lines == [
        "cap0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "input-a [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "cap1 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Captured Razer status frames around a synthetic input frame.
  @Test
  func capturedRazer() throws {
    let lines = transcript(
      try Self.captured(0x1532, 0x0A15),
      labels: .standard,
      Self.gipCapturedSteps(Self.capturedRazerStatus)
    )
    #expect(
      lines == [
        "cap0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "input-a [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "cap1 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Captured idle DualShock 4 USB reports.
  @Test
  func capturedDualShock4() throws {
    let lines = try transcript(Subjects.dualShock4USB, Self.capturedSteps(Self.capturedDualShock4))
    #expect(
      lines == [
        "cap0 [] hat=neutral ls=-1279,-1023 rs=767,0 lt=0 rt=0 motion=1 touch=1 fresh",
        "  motion n=12705 w=-0.0076,0.0164,0.0076 a=-0.0204,-2.1452,9.3182",
        "  touch primary [0:0:53002,6755 1:0:0,0]", "  battery 100% full wired-power=yes",
        "cap1 [] hat=neutral ls=-255,-1023 rs=511,0 lt=0 rt=0 motion=1 touch=1 fresh",
        "  motion n=13448 w=-0.0087,0.0175,0.0076 a=-0.0287,-2.1632,9.3075",
        "  touch primary [0:0:53002,6755 1:0:0,0]",
        "cap2 [] hat=neutral ls=-1279,-1023 rs=511,0 lt=0 rt=0 motion=1 touch=1 fresh",
        "  motion n=14191 w=-0.0087,0.0164,0.0076 a=-0.0263,-2.1512,9.3230",
        "  touch primary [0:0:53002,6755 1:0:0,0]",
      ]
    )
  }

  /// Captured idle Sixaxis reports.
  @Test
  func capturedSixaxis() throws {
    let lines = try transcript(Subjects.sixaxisUSB, Self.capturedSteps(Self.capturedSixaxis))
    #expect(
      lines == [
        "cap0 [] hat=neutral ls=-1279,258 rs=258,0 lt=0 rt=0",
        "cap1 [] hat=neutral ls=-1023,258 rs=258,0 lt=0 rt=0",
        "cap2 [] hat=neutral ls=-1279,258 rs=258,0 lt=0 rt=0",
      ]
    )
  }

  /// Switch Pro 0x30 IMU after an SPI factory-calibration reply. The reply sets gyro offsets
  /// (10, -20, 30) and a 9360-count gyro range, so 936 °/s over 9360 counts is 0.1 °/s per count
  /// after the offset; the accel range of 8192 counts gives 4 g / 8192 per count, no offset.
  /// Pro maps calibrated raw (x, y, z) to canonical (-y, x, z). Expected values, by hand:
  /// - sample 0: gyro raw (110, 480, -270) → (10, 50, -30) °/s → (-50, 10, -30) °/s
  ///   = (-0.8727, 0.1745, -0.5236) rad/s; accel raw (512, -4096, -3072) → (0.25, -2, -1.5) g
  ///   → (2, 0.25, -1.5) g = (19.6133, 2.4517, -14.7100) m/s².
  /// - sample 1: zero raw leaves the negated offsets, (-1, 2, -3) °/s → (-2, -1, -3) °/s
  ///   = (-0.0349, -0.0175, -0.0524) rad/s; zero acceleration.
  /// - sample 2: sample 0's calibrated values negated.
  @Test
  func switchUSBFactoryCalibratedMotion() throws {
    let driver = try driver(Subjects.switchUSB)
    _ = driver.startupWrites()
    var reply = [UInt8](repeating: 0, count: 49)
    reply[0] = 0x21
    reply.replaceSubrange(13..<20, with: [0x90, 0x10, 0x20, 0x60, 0, 0, 24])
    for (axis, offset) in [10, -20, 30].enumerated() {
      Self.write(0, into: &reply, at: 20 + axis * 2)
      Self.write(8192, into: &reply, at: 26 + axis * 2)
      Self.write(Int16(offset), into: &reply, at: 32 + axis * 2)
      Self.write(Int16(offset + 9360), into: &reply, at: 38 + axis * 2)
    }
    var report = Array(ProtocolPacketFixtures.SwitchPro.inputReport())
    let samples: [(accel: [Int16], gyro: [Int16])] = [
      ([512, -4096, -3072], [110, 480, -270]), ([0, 0, 0], [0, 0, 0]),
      ([-512, 4096, 3072], [-90, -520, 330]),
    ]
    for (index, sample) in samples.enumerated() {
      for axis in 0..<3 {
        Self.write(sample.accel[axis], into: &report, at: 13 + index * 12 + axis * 2)
        Self.write(sample.gyro[axis], into: &report, at: 19 + index * 12 + axis * 2)
      }
    }
    let lines = transcript(
      driver,
      labels: ControllerButtonLabels(protocolID: Subjects.switchUSB.protocolID),
      [Step("reply", reply), Step("imu", report)]
    )
    #expect(
      lines == [
        "reply [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "imu [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0 motion=3 touch=0",
        "  motion n=0 w=-0.8727,0.1745,-0.5236 a=19.6133,2.4517,-14.7100",
        "  motion n=0 w=-0.0349,-0.0175,-0.0524 a=0.0000,0.0000,0.0000",
        "  motion n=0 w=0.8727,-0.1745,0.5236 a=-19.6133,-2.4517,14.7100",
      ]
    )
  }

  /// Steam Controller IMU at the nominal scale, 2000 °/s and 2 g per 32768 counts, with SDL's
  /// gyro (x, -y, z) and accel (x, y, z). Expected values, by hand: gyro raw (2048, -4096, 8192)
  /// → (125, -250, 500) °/s → (125, 250, 500) °/s = (2.1817, 4.3633, 8.7266) rad/s; accel raw
  /// (4096, -32768, 24576) → (0.25, -2, 1.5) g = (2.4517, -19.6133, 14.7100) m/s².
  @Test
  func steamWiredMotion() throws {
    typealias Steam = ProtocolPacketFixtures.Steam
    let base = Array(Steam.inputReport())
    var report = base
    report[4] = 1
    for (axis, value) in [4096, -32768, 24576].enumerated() {
      Steam.writeInt16LE(Int16(value), into: &report, at: 28 + axis * 2)
    }
    for (axis, value) in [2048, -4096, 8192].enumerated() {
      Steam.writeInt16LE(Int16(value), into: &report, at: 34 + axis * 2)
    }
    let lines = try transcript(Subjects.steamWired, [Step("neutral", base), Step("imu", report)])
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0 motion=1 touch=2",
        "  motion n=0 w=0.0000,0.0000,0.0000 a=0.0000,0.0000,0.0000",
        "  touch left [0:0:32768,32767]", "  touch right [0:0:32768,32767]",
        "imu [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0 motion=1 touch=2",
        "  motion n=1 w=2.1817,4.3633,8.7266 a=2.4517,-19.6133,14.7100",
        "  touch left [0:0:32768,32767]", "  touch right [0:0:32768,32767]",
      ]
    )
  }

  private static func write(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
    let raw = UInt16(bitPattern: value)
    bytes[offset] = UInt8(truncatingIfNeeded: raw)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }
}
