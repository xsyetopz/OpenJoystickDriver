import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Sets who serves the controller model in the user's record for it.
  ///
  /// The record watcher then applies the change to every connected controller of the model without
  /// a replug.
  public func setControllerServer(
    vendorID: Int,
    productID: Int,
    server: ControllerServer
  ) async -> ControllerServerResult {
    let systemGamepadConnected = await connectedDevices().contains {
      $0.vendorID == vendorID && $0.productID == productID
        && $0.physicalOwnership == .systemGamepad
    }
    let result = Self.setControllerServer(
      vendorID: vendorID,
      productID: productID,
      server: server,
      systemGamepadConnected: systemGamepadConnected
    )
    if result.failure == nil { NotificationCenter.postServiceStatusChanged(from: self) }
    return result
  }

  /// Writes `server` to the model's user record in `directory`.
  ///
  /// A raw-USB family, or a model macOS does not serve natively, is refused; a model whose record
  /// already gives it to OJD counts as native, because OJD seized a controller macOS would serve.
  static func setControllerServer(
    vendorID: Int,
    productID: Int,
    server: ControllerServer,
    systemGamepadConnected: Bool,
    directory: URL = ControllerRecordSet.userDirectory
  ) -> ControllerServerResult {
    let records = ControllerRecordSet.load(userDirectory: directory)
    func refused(
      _ failure: ControllerServerFailure,
      _ previous: ControllerServer = .system,
      detail: String? = nil
    ) -> ControllerServerResult {
      ControllerServerResult(
        server: server,
        previous: previous,
        file: nil,
        created: false,
        failure: failure,
        detail: detail
      )
    }
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return refused(.invalidRequest)
    }
    let model = ControllerModelID(vendorID: vendor, productID: product)
    let record = records.records[model]
    let previous = record?.server ?? .system
    if record?.usesRawUSB == true { return refused(.rawUSB, previous) }
    guard systemGamepadConnected || previous == .ojd else { return refused(.notNative, previous) }
    let change: ControllerRecordWriter.Change
    do {
      change = try ControllerRecordWriter.change(
        server,
        for: model,
        records: records,
        directory: directory
      )
    } catch {
      switch error {
      case .noRecord: return refused(.noRecord, previous)
      case .invalidFile(let problem), .invalidResult(let problem):
        return refused(.invalidRecord, previous, detail: problem)
      }
    }
    var failure: ControllerServerFailure?
    var detail: String?
    do { try ControllerRecordWriter.write(change) } catch {
      failure = .persistenceFailed
      detail = error.localizedDescription
    }
    return ControllerServerResult(
      server: server,
      previous: change.previousServer,
      file: change.file.path,
      created: change.created,
      failure: failure,
      detail: detail
    )
  }
}
