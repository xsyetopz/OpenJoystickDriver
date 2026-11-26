import Testing

@testable import OpenJoystickDriverKit

struct ProfileValueSettingTests {
  @Test
  func emptyKeyReplacesTheValue() {
    #expect(ProfileValue.integer(1).setting(.integer(2), at: []) == .integer(2))
  }

  @Test
  func objectMemberIsSetAndNullRemovesIt() {
    let object = ProfileValue.object(["a": .integer(1)])
    #expect(
      object.setting(.integer(2), at: ["b"]) == .object(["a": .integer(1), "b": .integer(2)])
    )
    #expect(object.setting(.null, at: ["a"]) == .object([:]))
  }

  @Test
  func nestedKeyWithoutParentIsNil() {
    let object = ProfileValue.object(["a": .object([:])])
    #expect(object.setting(.integer(1), at: ["missing", "x"]) == nil)
    #expect(
      object.setting(.integer(1), at: ["a", "x"]) == .object(["a": .object(["x": .integer(1)])])
    )
  }

  @Test
  func arrayIndexReplacesAppendsAndRemoves() {
    let array = ProfileValue.array([.integer(1), .integer(2)])
    #expect(array.setting(.integer(9), at: ["1"]) == .array([.integer(1), .integer(9)]))
    #expect(
      array.setting(.integer(3), at: ["2"]) == .array([.integer(1), .integer(2), .integer(3)])
    )
    #expect(array.setting(.null, at: ["0"]) == .array([.integer(2)]))
    #expect(array.setting(.null, at: ["2"]) == nil)
    #expect(array.setting(.integer(3), at: ["3"]) == nil)
    #expect(array.setting(.integer(3), at: ["-1"]) == nil)
    #expect(array.setting(.integer(3), at: ["x"]) == nil)
  }

  @Test
  func scalarHasNoChildren() {
    #expect(ProfileValue.string("s").setting(.integer(1), at: ["a"]) == nil)
  }
}
