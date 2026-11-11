extension ControllerRecordProblem {
  /// The problem whose message is the catalog key `rule`.
  ///
  /// The message takes the file as `%1$@`, then `arguments` from `%2$@`. `description` is the
  /// English reason that stays stable for the repository tool.
  static func rule(
    _ rule: String,
    _ arguments: [String],
    _ description: String
  ) -> ControllerRecordProblem {
    ControllerRecordProblem(
      code: .invalidControllerRecord,
      key: rule,
      arguments: arguments,
      description
    )
  }

  /// The problem whose message is the catalog key `rule` and takes only the file.
  static func rule(_ rule: String, _ description: String) -> ControllerRecordProblem {
    self.rule(rule, [], description)
  }
}
