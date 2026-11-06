import ArgumentParser

extension CLI {
  /// The `kind` of each command's `--json` output: one table, not derived from the command path.
  ///
  /// A command whose output has another kind in some mode passes it to ``CLIOutput/json(_:kind:)``:
  /// `ojd access grant --token`, `ojd controller watch --first-press`, `ojd log show -f`.
  /// Commands that print no `--json` document of their own, such as `profile export`, are absent.
  static let outputKinds: [ObjectIdentifier: String] = {
    let table: [(any ParsableCommand.Type, String)] = [
      (StatusCommand.self, "SystemStatus"),
      (ControllerListCommand.self, "ControllerList"),
      (ControllerShowCommand.self, "Controller"),
      (ControllerWatchCommand.self, "ControllerState"),
      (ControllerCaptureCommand.self, "RawReport"),
      (ControllerCalibrateCommand.self, "Calibration"),
      (ControllerSuspendCommand.self, "ControllerSession"),
      (ControllerResumeCommand.self, "ControllerSession"),
      (ControllerDisconnectCommand.self, "ControllerSession"),
      (ControllerRumbleCommand.self, "Status"),
      (ControllerLightCommand.self, "Status"),
      (ControllerPlayerCommand.self, "Status"),
      (ControllerPairCommand.self, "ControllerPair"),
      (ControllerUnpairCommand.self, "ControllerPair"),
      (ControllerClaimCommand.self, "ControllerServer"),
      (ControllerReleaseCommand.self, "ControllerServer"),
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
      (ConfigSetCommand.self, "ConfigChange"),
      (ConfigUnsetCommand.self, "ConfigChange"),
      (DiagnoseCommand.self, "Diagnosis"),
      (ExplainCommand.self, "ErrorExplanation"),
      (TransportExtensionStatusCommand.self, "TransportExtension"),
      (TransportExtensionActivateCommand.self, "TransportExtension"),
      (TransportExtensionDeactivateCommand.self, "TransportExtension"),
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
      (SettingResetCommand.self, "Status"),
      (SettingTestNotificationCommand.self, "Status"),
      (RecordShowCommand.self, "ControllerRecord"),
      (RecordInstallCommand.self, "ControllerRecord"),
      (RecordListCommand.self, "ControllerRecordList"),
      (RecordDraftCommand.self, "RecordDraft"),
      (RecordTestCommand.self, "RecordTestResult"),
      (RecordValidateCommand.self, "RecordValidation"),
      (RecordRemoveCommand.self, "Status"),
      (ModValidateCommand.self, "ModPackageValidation"),
      (ModInstallCommand.self, "ModPackage"),
      (ModListCommand.self, "ModPackageList"),
      (ModRemoveCommand.self, "Status"),
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
      (VirtualExportMappingCommand.self, "VirtualGamepadMapping"),
    ]
    return Dictionary(uniqueKeysWithValues: table.map { (ObjectIdentifier($0.0), $0.1) })
  }()

  /// The JSON output kind of a command, or nil for a command that is not in the table.
  static func outputKind(of command: any ParsableCommand.Type) -> String? {
    outputKinds[ObjectIdentifier(command)]
  }
}
