/// The `status` of a ``CLIStatus``, spelled as in Kubernetes.
enum CLIStatusOutcome: String, Encodable {
  case success = "Success"
  case failure = "Failure"
}

/// The `--json` result of an action that leaves no object to print: a Kubernetes `Status`.
///
/// `details` is the command's own result. The `kind` is `Status`, from `CLI.outputKinds`.
struct CLIStatus<Details: Encodable>: Encodable {
  let status: CLIStatusOutcome
  let details: Details

  init(_ status: CLIStatusOutcome = .success, details: Details) {
    self.status = status
    self.details = details
  }
}
