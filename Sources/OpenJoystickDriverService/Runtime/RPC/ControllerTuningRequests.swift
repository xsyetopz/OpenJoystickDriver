import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Sets `key` to `value` in the model's user record, or removes it when `value` is nil.
  ///
  /// The record watcher then applies the change to every connected controller of the model without
  /// a replug.
  public func setControllerTuning(
    vendorID: Int,
    productID: Int,
    key: ControllerTuning.Key,
    value: Double?
  ) -> ControllerTuningResult {
    let result = Self.setControllerTuning(
      vendorID: vendorID,
      productID: productID,
      key: key,
      value: value
    )
    if result.failure == nil { NotificationCenter.postServiceStatusChanged(from: self) }
    return result
  }

  /// Writes `key` to the model's user record in `directory`.
  ///
  /// A value the record refuses, such as a `stickDeadzone` out of range, changes nothing.
  static func setControllerTuning(
    vendorID: Int,
    productID: Int,
    key: ControllerTuning.Key,
    value: Double?,
    directory: URL = ControllerRecordSet.userDirectory
  ) -> ControllerTuningResult {
    func refused(
      _ failure: ControllerTuningFailure,
      detail: String? = nil
    ) -> ControllerTuningResult {
      ControllerTuningResult(
        key: key,
        value: value,
        previous: nil,
        file: nil,
        created: false,
        failure: failure,
        detail: detail
      )
    }
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return refused(.invalidRequest)
    }
    let edit: ControllerRecordWriter.TuningEdit = value.map { .set(key, $0) } ?? .remove(key)
    let change: ControllerRecordWriter.Change
    do {
      change = try ControllerRecordWriter.change(
        edit,
        for: .model(ControllerModelID(vendorID: vendor, productID: product)),
        records: ControllerRecordSet.load(userDirectory: directory),
        directory: directory
      )
    } catch {
      switch error {
      case .notSet: return refused(.notSet)
      case .refused(.noRecord): return refused(.noRecord)
      case .refused(.invalidFile(let problem)), .refused(.invalidResult(let problem)):
        return refused(.invalidRecord, detail: problem)
      }
    }
    var failure: ControllerTuningFailure?
    var detail: String?
    do { try ControllerRecordWriter.write(change) } catch {
      failure = .persistenceFailed
      detail = error.localizedDescription
    }
    return ControllerTuningResult(
      key: key,
      value: value,
      previous: change.previousTuning,
      file: change.file.path,
      created: change.created,
      failure: failure,
      detail: detail
    )
  }
}
