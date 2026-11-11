import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct VirtualGamepadMappingTests {
  @Test
  func theGenericPersonaUsesTheCRCLessGUIDAndThePublishedButtonUsages() throws {
    let mapping = try VirtualHIDProfileID.generic.gamepadMapping()
    #expect(mapping.guid == "03000000091200004f4a000008040000")
    #expect(
      mapping.sdlMapping
        == "03000000091200004f4a000008040000,OpenJoystickDriver Generic HID Gamepad,"
        + "a:b0,b:b1,x:b2,y:b3,back:b6,guide:b14,start:b7,leftstick:b8,rightstick:b9,"
        + "leftshoulder:b4,rightshoulder:b5,dpup:b10,dpdown:b11,dpleft:b12,dpright:b13,misc1:b15,"
        + "leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:+a4,righttrigger:+a5,"
        + "platform:Mac OS X,"
    )
  }

  @Test
  func theSDLCompatiblePersonaReadsTheDpadAsButtonsAndBindsBothYAxesInverted() throws {
    let mapping = try VirtualHIDProfileID.sdlCompatible.gamepadMapping()
    #expect(mapping.guid == "030000005e0400000c0b000000000000")
    #expect(mapping.sdlMapping.contains("dpup:b"))
    #expect(mapping.sdlMapping.contains("lefty:a1~,"))
    #expect(mapping.sdlMapping.contains("righty:a4~,"))
    #expect(mapping.sdlMapping.contains("lefttrigger:+a2,righttrigger:+a5,"))
    #expect(mapping.unmapped.isEmpty)
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func theW3CDescriptionFollowsTheCrosswalk(id: VirtualHIDProfileID) throws {
    let mapping = try id.gamepadMapping()
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Resources/Vocabulary/crosswalk.plist")
    let root = try PropertyListFixture.dictionary(at: url)
    let controls = try #require(root["controls"] as? [String: [String: Any]])
    var buttons: [Int: String] = [:]
    var axes: [Int: String] = [:]
    for (name, entry) in controls {
      if let index = entry["w3cButton"] as? Int { buttons[index] = name }
      if let index = entry["w3cAxis"] as? Int { axes[index] = name }
    }
    #expect(
      mapping.w3cButtons.allSatisfy { buttons[$0.index] == $0.control.rawValue },
      "\(mapping.w3cButtons)"
    )
    #expect(
      mapping.w3cAxes.allSatisfy { axes[$0.index] == $0.control.rawValue },
      "\(mapping.w3cAxes)"
    )
    #expect(mapping.w3cAxes.count == 4)
    #expect(mapping.w3cButtons.map(\.index) == mapping.w3cButtons.map(\.index).sorted())
  }

  @Test
  func everyNameInTheTableMatchesTheCrosswalk() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Resources/Vocabulary/crosswalk.plist")
    let root = try PropertyListFixture.dictionary(at: url)
    let controls = try #require(root["controls"] as? [String: [String: Any]])
    // SDL3's element names as the crosswalk spells them, and the field a mapping string writes.
    let mappingKeys = [
      "SOUTH": "a", "EAST": "b", "WEST": "x", "NORTH": "y", "BACK": "back", "GUIDE": "guide",
      "START": "start", "LEFT_STICK": "leftstick", "RIGHT_STICK": "rightstick",
      "LEFT_SHOULDER": "leftshoulder", "RIGHT_SHOULDER": "rightshoulder", "DPAD_UP": "dpup",
      "DPAD_DOWN": "dpdown", "DPAD_LEFT": "dpleft", "DPAD_RIGHT": "dpright", "MISC1": "misc1",
      "RIGHT_PADDLE1": "paddle1", "LEFT_PADDLE1": "paddle2", "RIGHT_PADDLE2": "paddle3",
      "LEFT_PADDLE2": "paddle4", "TOUCHPAD": "touchpad", "LEFTX": "leftx", "LEFTY": "lefty",
      "RIGHTX": "rightx", "RIGHTY": "righty", "LEFT_TRIGGER": "lefttrigger",
      "RIGHT_TRIGGER": "righttrigger",
    ]
    for (control, names) in ControlNames.table {
      let id = control.rawValue
      let entry = try #require(controls[id], "\(id) is not in the crosswalk")
      let sdl = entry["sdl"] as? String
      #expect(sdl.flatMap { mappingKeys[$0] } == names.sdl, "\(id) SDL: \(sdl ?? "null")")
      #expect(entry["w3cButton"] as? Int == names.w3cButton, "\(id) W3C button")
      #expect(entry["w3cAxis"] as? Int == names.w3cAxis, "\(id) W3C axis")
    }
    #expect(Set(ControlNames.sdlFieldOrder) == Set(ControlNames.table.values.map(\.sdl)))
  }

  @Test
  func thePersonaDefinitionStatesWhetherSDLWorksWithItsDefaultHints() throws {
    #expect(VirtualHIDProfileID.generic.worksWithDefaultSDLHints)
    #expect(VirtualHIDProfileID.sdlCompatible.worksWithDefaultSDLHints)
    for id in VirtualHIDProfileID.allCases {
      #expect(try id.gamepadMapping().worksWithDefaultSDLHints == id.worksWithDefaultSDLHints)
    }
  }
}
