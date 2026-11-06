#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  /// What the Input Test window needs from the service: input state, output commands and color
  /// preview.
  protocol InputTestDeviceGateway: MotionCalibrationGateway {
    /// Returns the latest input of the controller, or nil when there is none yet.
    ///
    /// - Parameter selector: The controller.
    /// - Returns: The latest input of the controller, or nil when there is none yet.
    /// - Throws: The error of the request.
    func controllerState(for selector: ControllerReference) async throws -> ControllerState?
    /// Sends an output command to the controller.
    ///
    /// - Parameters:
    ///   - command: The output command.
    ///   - selector: The controller.
    /// - Returns: The result, which says whether the controller received the command.
    /// - Throws: The error of the request.
    func sendControllerOutput(
      _ command: ControllerOutputCommand,
      for selector: ControllerReference
    ) async throws -> ControllerOutputResult
    /// Previews a color on the controller's lighting until the preview is released.
    ///
    /// - Parameters:
    ///   - selector: The controller.
    ///   - token: Names the preview.
    ///   - red: The red component, 0 to 255.
    ///   - green: The green component, 0 to 255.
    ///   - blue: The blue component, 0 to 255.
    /// - Returns: Whether the request succeeded.
    /// - Throws: The error of the request.
    func previewColor(
      for selector: ControllerReference,
      token: UUID,
      red: UInt8,
      green: UInt8,
      blue: UInt8
    ) async throws -> Bool
    /// Ends the preview of `token` so that the controller shows its own color.
    ///
    /// - Parameters:
    ///   - selector: The controller.
    ///   - token: Names the preview.
    /// - Returns: Whether the request succeeded.
    /// - Throws: The error of the request.
    func releaseColorPreview(for selector: ControllerReference, token: UUID) async throws -> Bool
  }

  /// View-owned physical-output values are isolated from session state so continuous controls do
  /// not invalidate the live input hierarchy or window chrome while they are being dragged.
  @MainActor
  final class InputTestOutputSettings: ObservableObject {
    /// The rumble intensity of each motor, 0 to 255.
    @Published
    var rumbleIntensities: [PhysicalRumbleMotor: Double] = [:]
    /// The rumble test length in milliseconds.
    @Published
    var rumbleDurationMilliseconds = 300.0
    /// The player indicator to apply.
    @Published
    var playerIndicator: PhysicalPlayerIndicator = .off
    /// The red component of the color to apply, 0 to 255.
    @Published
    var red = 0.0
    /// The green component of the color to apply, 0 to 255.
    @Published
    var green = 122.0
    /// The blue component of the color to apply, 0 to 255.
    @Published
    var blue = 255.0
    /// The brightness to apply, 0 to 255.
    @Published
    var brightness = 255.0
  }

  /// The state of the Input Test window: the selected controller, the sampling session and the
  /// output tests.
  @MainActor
  final class InputTestViewModel: ObservableObject {
    /// The selected controller, or nil.
    @Published
    var device: ApplicationServiceDeviceDescription?
    /// Where the sampling of the controller's input is.
    @Published
    var sessionState: SessionState = .idle
    /// Where the latest output test is.
    @Published
    var outputState: OutputState = .idle
    /// The message of the latest failed output test, or nil.
    @Published
    var outputError: String?
    /// Whether the selected controller is among the connected ones.
    @Published
    var isDeviceConnected = false
    /// The high-frequency input state.
    let liveState = InputTestLiveState()
    /// The values of the output controls.
    let outputSettings = InputTestOutputSettings()
    /// The model of the Motion section.
    let motionCalibration: MotionCalibrationViewModel

    /// The gateway to the service.
    let gateway: any InputTestDeviceGateway
    /// The time between two samples of the input, in nanoseconds.
    let sampleIntervalNanoseconds: UInt64
    /// Waits between two samples.
    let sleep: Sleep
    /// Waits for the length of a rumble test.
    let rumbleSleep: Sleep
    /// The task that samples the input, or nil.
    var samplingTask: Task<Void, Never>?
    /// The task of the running output test, or nil.
    var outputTask: Task<Void, Never>?
    /// Names the latest sampling; an earlier one that ends later changes nothing.
    var samplingGeneration: UInt64 = 0
    /// Whether the window is open.
    var isWindowActive = false
    /// Names the latest output test; an earlier one that ends later changes nothing.
    var outputGeneration: UInt64 = 0
    /// The controller of the running output test, or nil.
    var outputSelector: ControllerReference?
    /// Whether the running output test is a rumble that must be stopped.
    var outputMayRequireRumbleStop = false
    /// Names the color preview of this window.
    let colorPreviewToken = UUID()
    /// The controller that shows the color preview, or nil.
    var colorPreviewSelector: ControllerReference?

    /// Creates the model on `gateway`.
    ///
    /// - Parameters:
    ///   - gateway: The gateway to the service.
    ///   - sampleIntervalNanoseconds: The time between two samples of the input.
    ///   - sleep: Waits between two samples.
    ///   - rumbleSleep: Waits for the length of a rumble test.
    init(
      gateway: any InputTestDeviceGateway,
      sampleIntervalNanoseconds: UInt64 = 33_333_333,
      sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) },
      rumbleSleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
      self.gateway = gateway
      motionCalibration = MotionCalibrationViewModel(gateway: gateway)
      self.sampleIntervalNanoseconds = sampleIntervalNanoseconds
      self.sleep = sleep
      self.rumbleSleep = rumbleSleep
    }
  }

#endif
