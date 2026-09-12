import Testing

@testable import OpenJoystickDriver
import OpenJoystickDriverKit

struct PhysicalOutputCommandValueTests {
  @Test(arguments: [
    "physical:rumble:rightTrigger:0.25",
    "physical:player:3",
    "physical:color:12:34:56",
    "physical:brightness:0.75",
    "physical:adaptive:left:off",
    "physical:adaptive:right:resistance:0.4:0.8",
  ]) func rendererRoundTripsEveryPhysicalTarget(_ rawValue: String) throws {
    let destination = try MappingSyntax.destination(rawValue)
    #expect(try MappingSyntax.destination(MappingRenderer.destination(destination)) == destination)
  }

  @Test func localizedHelpIncludesPhysicalTargetGrammar() {
    #expect(MappingInvocation.help.contains("physical:adaptive:<left|right>:resistance"))
  }
}
