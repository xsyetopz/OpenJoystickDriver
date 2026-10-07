import ArgumentParser

extension CLI {
  /// The `kind` of each command's `--json` output: one table, not derived from the command path.
  ///
  /// A command whose output has another kind in some mode passes it to `CLIOutput.json(_:kind:)`:
  /// `ojd access grant --token`, `ojd controller watch --first-press`, `ojd log show -f`.
  /// Commands that print no `--json` document of their own, such as `profile export`, are absent.
  static let outputKinds: [ObjectIdentifier: String] = {
    let table: [(any ParsableCommand.Type, String)] = [
      (StatusCommand.self, "SystemStatus"),
      (ControllerListCommand.self, "ControllerList"),
      (ControllerShowCommand.self, "Controller"),
      (ControllerWatchCommand.self, "ControllerState"),
      (ControllerCaptureCommand.self, "USBPacket"),
      (ControllerCalibrateCommand.self, "Calibration"),
      (ControllerSuspendCommand.self, "ControllerSession"),
      (ControllerResumeCommand.self, "ControllerSession"),
      (ControllerDisconnectCommand.self, "ControllerSession"),
      (ControllerRumbleCommand.self, "Status"),
      (ControllerLightCommand.self, "Status"),
      (ControllerPlayerCommand.self, "Status"),
      (ControllerPairCommand.self, "JoyConPair"),
      (ControllerUnpairCommand.self, "JoyConPair"),
      (AccessEnableCommand.self, "EndpointAccess"),
      (AccessDisableCommand.self, "EndpointAccess"),
      (AccessStatusCommand.self, "EndpointAccess"),
      (AccessWebEnableCommand.self, "WebAccess"),
      (AccessWebDisableCommand.self, "WebAccess"),
      (AccessGrantCommand.self, "AccessGrant"),
      (AccessListCommand.self, "AccessSummary"),
      (AccessRevokeCommand.self, "Status"),
      (BindingListCommand.self, "BindingList"),
      (BindingSetCommand.self, "Binding"),
      (BindingClearCommand.self, "Status"),
      (ConfigShowCommand.self, "Configuration"),
      (DiagnoseCommand.self, "Diagnosis"),
      (ExplainCommand.self, "ErrorExplanation"),
      (ExtensionStatusCommand.self, "DriverExtension"),
      (ExtensionActivateCommand.self, "DriverExtension"),
      (ExtensionDeactivateCommand.self, "DriverExtension"),
      (LogPathCommand.self, "LogLocation"),
      (LogShowCommand.self, "LogSnapshot"),
      (LogExportCommand.self, "Status"),
      (PermissionListCommand.self, "PermissionList"),
      (PermissionRequestCommand.self, "PermissionRequest"),
      (ProfileShowCommand.self, "Profile"),
      (ProfileCreateCommand.self, "Profile"),
      (ProfileSetCommand.self, "Profile"),
      (ProfileRenameCommand.self, "Profile"),
      (ProfileDuplicateCommand.self, "Profile"),
      (ProfileActivateCommand.self, "Profile"),
      (ProfileDeactivateCommand.self, "Profile"),
      (ProfileImportCommand.self, "Profile"),
      (ProfileGetCommand.self, "ProfileValue"),
      (ProfileListCommand.self, "ProfileList"),
      (ProfileValidateCommand.self, "ProfileValidation"),
      (ProfileDeleteCommand.self, "Status"),
      (ProfileRecoverCommand.self, "Status"),
      (RecordShowCommand.self, "ControllerRecord"),
      (RecordInstallCommand.self, "ControllerRecord"),
      (RecordListCommand.self, "ControllerRecordList"),
      (RecordDraftCommand.self, "RecordDraft"),
      (RecordTestCommand.self, "RecordTestResult"),
      (RecordValidateCommand.self, "RecordValidation"),
      (RecordRemoveCommand.self, "Status"),
      (ServiceStartCommand.self, "Service"),
      (ServiceStopCommand.self, "Service"),
      (ServiceWaitCommand.self, "Service"),
      (SettingGetCommand.self, "Setting"),
      (SettingSetCommand.self, "Setting"),
      (SettingListCommand.self, "SettingList"),
      (UpdateCheckCommand.self, "UpdateCheck"),
      (VirtualShowCommand.self, "VirtualGamepadConfiguration"),
      (VirtualSetCommand.self, "VirtualGamepadChange"),
      (VirtualResetCommand.self, "VirtualGamepadChange"),
      (VirtualFeedCommand.self, "RumbleCommand"),
    ]
    return Dictionary(uniqueKeysWithValues: table.map { (ObjectIdentifier($0.0), $0.1) })
  }()

  /// The `kind` of `command`'s `--json` output, or nil for a command that is not in the table.
  static func outputKind(of command: any ParsableCommand.Type) -> String? {
    outputKinds[ObjectIdentifier(command)]
  }
}
