/// The `status` of a ``CLIStatus``, spelled as in Kubernetes.
enum CLIStatusOutcome: String, Encodable {
  /// The action succeeded.
  case success = "Success"
  /// The action failed.
  case failure = "Failure"
}

/// The `--json` result of an action that leaves no object to print: a Kubernetes `Status`.
///
/// `details` is the command's own result. The `kind` is `Status`, from ``CLI/outputKinds``.
struct CLIStatus<Details: Encodable>: Encodable {
  /// Whether the action succeeded.
  let status: CLIStatusOutcome
  /// The command's own result.
  let details: Details

  /// Creates the status with `details`.
  init(_ status: CLIStatusOutcome = .success, details: Details) {
    self.status = status
    self.details = details
  }
}
