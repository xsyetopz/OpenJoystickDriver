import Foundation

func littleEndianBytes(_ value: Int16) -> (UInt8, UInt8) {
  let raw = UInt16(bitPattern: value)
  return (UInt8(raw & 0xFF), UInt8(raw >> 8))
}

func makeDS4Report(
  includesReportID: Bool = false,
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: includesReportID ? 64 : 63)
  let base = includesReportID ? 1 : 0
  if includesReportID { report[0] = 0x01 }
  report[base + 0] = leftStickX
  report[base + 1] = leftStickY
  report[base + 2] = rightStickX
  report[base + 3] = rightStickY
  report[base + 4] = buttons0
  report[base + 5] = buttons1
  report[base + 6] = buttons2
  report[base + 7] = leftTrigger
  report[base + 8] = rightTrigger
  return Data(report)
}

func makeDS4BluetoothReport(
  includesHIDTransaction: Bool = false,
  includesReportID: Bool = true,
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0
) -> Data {
  var report: [UInt8] = []
  if includesHIDTransaction { report.append(0xA1) }
  if includesReportID { report.append(0x11) }
  report.append(contentsOf: [0xC0, 0x00])
  report.append(contentsOf: [
    leftStickX, leftStickY, rightStickX, rightStickY, buttons0, buttons1, buttons2, leftTrigger,
    rightTrigger,
  ])
  report.append(contentsOf: [UInt8](repeating: 0, count: 64))
  report.append(contentsOf: [0x7D, 0x0A, 0x5D, 0x0B])
  return Data(report)
}

func makeXbox360ReportLE(
  buttons: UInt16 = 0,
  lt: UInt8 = 0,
  rt: UInt8 = 0,
  lsx: Int16 = 0,
  lsy: Int16 = 0,
  rsx: Int16 = 0,
  rsy: Int16 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 20)
  report[0] = 0x00
  report[1] = 0x14
  report[2] = UInt8(buttons & 0xFF)
  report[3] = UInt8(buttons >> 8)
  report[4] = lt
  report[5] = rt
  let (lsxL, lsxH) = littleEndianBytes(lsx)
  let (lsyL, lsyH) = littleEndianBytes(lsy)
  let (rsxL, rsxH) = littleEndianBytes(rsx)
  let (rsyL, rsyH) = littleEndianBytes(rsy)
  report[6] = lsxL; report[7] = lsxH
  report[8] = lsyL; report[9] = lsyH
  report[10] = rsxL; report[11] = rsxH
  report[12] = rsyL; report[13] = rsyH
  return Data(report)
}
