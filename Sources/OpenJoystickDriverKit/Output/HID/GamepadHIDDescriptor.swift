import Foundation

/// Standard HID GamePad report descriptor used by OpenJoystickDriver virtual devices.
///
/// This descriptor is intentionally generic (HID Usage Page: Generic Desktop, Usage: GamePad).
/// Do not assume consumers will apply device-specific parsing based on VID/PID.
///
/// Report layout (14 bytes total):
///   Bytes 0–1: Button usages 1–6 and 9–18
///   Bytes 2–3: Left Stick X  (Int16 LE, –32767...32767) — Usage: X  (0x30)
///   Bytes 4–5: Left Stick Y  (Int16 LE, –32767...32767) — Usage: Y  (0x31)
///   Bytes 6–7: Right Stick X (Int16 LE, –32767...32767) — Usage: Z  (0x32)
///   Bytes 8–9: Right Stick Y (Int16 LE, –32767...32767) — Usage: Rx (0x33)
///   Bytes 10–11: Left Trigger  (Int16 LE, 0...32767) — Usage: Ry (0x34)
///   Bytes 12–13: Right Trigger (Int16 LE, 0...32767) — Usage: Rz (0x35)
///
/// The device is input-only: the descriptor declares no output or feature report, so no
/// consumer output (rumble or otherwise) reaches the controller through it.
///
/// This layout is the published contract for OJD VID/PID `1209:4A4F`. An incompatible
/// descriptor or report-layout change must use a new product ID.
public enum GamepadHIDDescriptor {
  // MARK: - Report descriptor bytes

  // Indentation reflects HID descriptor hierarchy — intentionally not vertically aligned.
  /// Raw HID report descriptor that describes the virtual gamepad layout.
  public static let descriptor: [UInt8] = [
    // ----- Usage Page: Generic Desktop -----
    0x05, 0x01,
    // Usage: Gamepad
    0x09, 0x05,
    // Collection: Application
    0xA1, 0x01,
    // Collection: Physical
    0xA1, 0x00,

    // --- Button usages 1–6 and 9–18; omit Blink trigger slots B6/B7 ---
    0x05, 0x09,  // Usage Page: Button
    0x19, 0x01,  // Usage Minimum: 1
    0x29, 0x06,  // Usage Maximum: 6
    0x15, 0x00,  // Logical Minimum: 0
    0x25, 0x01,  // Logical Maximum: 1
    0x75, 0x01,  // Report Size: 1
    0x95, 0x06,  // Report Count: 6
    0x81, 0x02,  // Input: Data, Variable, Absolute

    0x19, 0x09,  // Usage Minimum: 9
    0x29, 0x12,  // Usage Maximum: 18
    0x95, 0x0A,  // Report Count: 10
    0x81, 0x02,  // Input: Data, Variable, Absolute

    // --- Six axes on the Generic Desktop page ---
    // Blink indexes raw macOS HID axes by usage: X, Y, Z, Rx, Ry, Rz.
    0x05, 0x01,  // Usage Page: Generic Desktop

    // LSX=X, LSY=Y, RSX=Z, RSY=Rx, LT=Ry, RT=Rz.
    0x09, 0x30,  // Usage: X  (left stick X)
    0x09, 0x31,  // Usage: Y  (left stick Y)
    0x09, 0x32,  // Usage: Z  (right stick X)
    0x09, 0x33,  // Usage: Rx (right stick Y)
    0x09, 0x34,  // Usage: Ry (left trigger)
    0x09, 0x35,  // Usage: Rz (right trigger)
    0x16, 0x01, 0x80,  // Logical Minimum: -32767
    0x26, 0xFF, 0x7F,  // Logical Maximum:  32767
    0x75, 0x10,  // Report Size: 16
    0x95, 0x06,  // Report Count: 6
    0x81, 0x02,  // Input: Data, Variable, Absolute

    0xC0,  // End Collection (Physical)
    0xC0,  // End Collection (Application)
  ]

  // MARK: - Report size

  /// Total byte length of one input report.
  public static let reportSize = 14

  // MARK: - Hat switch values

  /// Normalized D-pad directions shared by virtual report formats.
  public enum Hat: UInt8, Sendable {
    /// Null / neutral — no direction pressed. Value below Logical Minimum,
    /// which the HID system interprets as the null state.
    case neutral = 0
    case north = 1
    case northEast = 2
    case east = 3
    case southEast = 4
    case south = 5
    case southWest = 6
    case west = 7
    case northWest = 8
  }

  // MARK: - Button bit indices (0-based)

  /// Button bit assignments matching Xbox One S Bluetooth HID order.
  ///
  /// SDL 2/3 mapping for 045E:02EA:
  /// a:b0, b:b1, x:b2, y:b3, leftshoulder:b4, rightshoulder:b5,
  /// leftstick:b6, rightstick:b7, start:b8, back:b9, guide:b10,
  /// dpup:b11, dpdown:b12, dpleft:b13, dpright:b14, misc1:b15
  public enum ButtonBit: Int {
    case a = 0  // Xbox A
    case b = 1  // Xbox B
    case x = 2  // Xbox X
    case y = 3  // Xbox Y
    case leftBumper = 4  // LB
    case rightBumper = 5  // RB
    case leftStick = 6  // LS click / L3
    case rightStick = 7  // RS click / R3
    case start = 8  // Start / Menu
    case back = 9  // Back / View
    case guide = 10  // Xbox / Guide
    case dpadUp = 11
    case dpadDown = 12
    case dpadLeft = 13
    case dpadRight = 14
    case share = 15
  }

  // MARK: - D-pad button bitmask helper

  /// Returns the button bitmask bits for D-pad directions (bits 11–14).
  /// Used alongside the hat switch for dual encoding.
  public static func dpadButtonBits(for hat: Hat) -> UInt32 {
    switch hat {
    case .neutral: return 0
    case .north: return 1 << 11
    case .northEast: return (1 << 11) | (1 << 14)
    case .east: return 1 << 14
    case .southEast: return (1 << 12) | (1 << 14)
    case .south: return 1 << 12
    case .southWest: return (1 << 12) | (1 << 13)
    case .west: return 1 << 13
    case .northWest: return (1 << 11) | (1 << 13)
    }
  }
}
