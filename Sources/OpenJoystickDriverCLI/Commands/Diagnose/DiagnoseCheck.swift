import Foundation

/// The outcome of one `ojd diagnose` check. The raw values are stable identifiers.
enum DiagnoseStatus: String, Encodable, Equatable, Sendable {
  case pass
  case warn
  case fail
  case skip
}

/// One `ojd diagnose` check: a stable kebab-case `id`, its `status`, and a one-line `detail`.
struct DiagnoseCheck: Encodable, Equatable, Sendable {
  let id: String
  let status: DiagnoseStatus
  let detail: String

  init(_ id: String, _ status: DiagnoseStatus, _ detail: String) {
    self.id = id
    self.status = status
    self.detail = detail
  }
}

/// The `ojd diagnose --json` result. `bundle` is absent unless `--bundle` wrote a file.
struct DiagnoseReport: Encodable, Equatable {
  let checks: [DiagnoseCheck]
  let bundle: String?

  var failureCount: Int { checks.filter { $0.status == .fail }.count }

  var plainRows: [[String]] { checks.map { [$0.id, $0.status.rawValue, $0.detail] } }
}
