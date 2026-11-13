import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverKit

struct CommandLineValueSpellingTests {
  @Test
  func permissionIDsAreUpperCamelCaseInJSONAndKebabCaseOnCommandLine() {
    #expect(
      PermissionID.allCases.map(\.rawValue) == [
        "InputRead", "InputInject", "USBTransport", "PostEvent",
      ]
    )
    #expect(
      PermissionID.allCases.map(\.commandLineName) == [
        "input-read", "input-inject", "usb-transport", "post-event",
      ]
    )
    #expect(CommandLineName.collisions(in: PermissionID.self).isEmpty)
    for permission in PermissionID.allCases {
      #expect(CommandLineName.value(of: permission.commandLineName) == permission)
    }
    for raw in ["inputRead", "InputRead", "usbTransport", "input_read"] {
      #expect(CommandLineName.value(of: raw, in: PermissionID.self) == nil, "\(raw)")
    }
    for raw in ["input-read", "input-inject", "usb-transport", "inputRead"] {
      #expect(PermissionID(rawValue: raw) == nil, "\(raw)")
    }
  }

  @Test
  func mappingFormatsAreUpperCaseInJSONAndLowercaseOnCommandLine() {
    #expect(VirtualMappingFormat.allCases.map(\.rawValue) == ["SDL", "W3C"])
    #expect(VirtualMappingFormat.allValueStrings == ["sdl", "w3c"])
    #expect(VirtualMappingFormat(argument: "sdl") == .sdl)
    #expect(VirtualMappingFormat(argument: "w3c") == .w3c)
    for raw in ["SDL", "W3C", "Sdl", "gamepad"] {
      #expect(VirtualMappingFormat(argument: raw) == nil, "\(raw)")
    }
    #expect(VirtualMappingFormat(rawValue: "sdl") == nil)
    #expect(VirtualMappingFormat(rawValue: "w3c") == nil)
  }

  @Test
  func statusReportEnumsAreUpperCamelCase() {
    #expect(ServiceStateResult.State.running.rawValue == "Running")
    #expect(TransportExtensionResult.State.awaitingApproval.rawValue == "AwaitingApproval")
    #expect(StatusReport.Extension.Bundle.invalid.rawValue == "Invalid")
    #expect(StatusReport.Extension.Registration.unavailable.rawValue == "Unavailable")
    #expect(UpdateCheckCommand.Result.Status.upToDate.rawValue == "UpToDate")
    #expect(
      UpdateCheckCommand.Result.Status.aheadOfLatestRelease.rawValue == "AheadOfLatestRelease"
    )
    #expect(RecordTransport.hid.rawValue == "HID")
    #expect(RecordTransport.usb.rawValue == "USB")
    #expect(RecordTransportClaim.claimed.rawValue == "Claimed")
    for raw in ["running", "stopped", "Run"] {
      #expect(ServiceStateResult.State(rawValue: raw) == nil)
    }
    for raw in ["active", "inactive", "awaitingApproval", "awaiting-approval"] {
      #expect(TransportExtensionResult.State(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["present", "missing", "invalid"] {
      #expect(StatusReport.Extension.Bundle(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["active", "inactive", "absent", "unavailable"] {
      #expect(StatusReport.Extension.Registration(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["hid", "usb", "Usb"] { #expect(RecordTransport(rawValue: raw) == nil, "\(raw)") }
    for raw in ["claimed", "unclaimed", "Unclaimed "] {
      #expect(RecordTransportClaim(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["upToDate", "available", "up-to-date"] {
      #expect(UpdateCheckCommand.Result.Status(rawValue: raw) == nil, "\(raw)")
    }
  }
}
