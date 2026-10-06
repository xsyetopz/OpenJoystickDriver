import Testing

@testable import OpenJoystickDriverCLI

struct CLITerminalTests {
  private let terminal: (Int32) -> Bool = { _ in true }

  @Test
  func colorNeedsATerminalWithoutOptOuts() {
    #expect(
      CLITerminal.usesColor(on: .standardOutput, context: CLIContext(), environment: [:]) { _ in
        true
      }
    )
    #expect(
      !CLITerminal.usesColor(on: .standardOutput, context: CLIContext(), environment: [:]) { _ in
        false
      }
    )
  }

  @Test(arguments: [["NO_COLOR": "1"], ["NO_COLOR": ""], ["TERM": "dumb"]])
  func environmentTurnsColorOff(environment: [String: String]) {
    #expect(
      !CLITerminal.usesColor(
        on: .standardError,
        context: CLIContext(),
        environment: environment,
        isTerminal: terminal
      )
    )
  }

  @Test
  func noColorFlagTurnsColorOff() {
    var context = CLIContext()
    context.noColor = true
    #expect(
      !CLITerminal.usesColor(
        on: .standardOutput,
        context: context,
        environment: [:],
        isTerminal: terminal
      )
    )
  }

  @Test
  func forceColorBeatsTheEnvironmentButNotTheNoColorFlag() {
    var context = CLIContext()
    context.forceColor = true
    let environment = ["NO_COLOR": "1", "TERM": "dumb"]
    #expect(
      CLITerminal.usesColor(on: .standardOutput, context: context, environment: environment) { _ in
        false
      }
    )
    context.noColor = true
    #expect(
      !CLITerminal.usesColor(
        on: .standardOutput,
        context: context,
        environment: environment,
        isTerminal: terminal
      )
    )
  }

  @Test
  func noInputForbidsPrompts() {
    var context = CLIContext()
    context.noInput = true
    #expect(!CLITerminal.canPrompt(context: context))
  }
}
