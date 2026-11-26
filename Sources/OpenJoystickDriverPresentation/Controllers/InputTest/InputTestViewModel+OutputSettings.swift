#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  extension InputTestViewModel {
    /// The rumble intensity of each motor, kept in the output settings.
    var rumbleIntensities: [PhysicalRumbleMotor: Double] {
      get { outputSettings.rumbleIntensities }
      set { outputSettings.rumbleIntensities = newValue }
    }

    /// The rumble test length in milliseconds, kept in the output settings.
    var rumbleDurationMilliseconds: Double {
      get { outputSettings.rumbleDurationMilliseconds }
      set { outputSettings.rumbleDurationMilliseconds = newValue }
    }

    /// The player indicator to apply, kept in the output settings.
    var playerIndicator: PhysicalPlayerIndicator {
      get { outputSettings.playerIndicator }
      set { outputSettings.playerIndicator = newValue }
    }

    /// The red component of the color to apply, kept in the output settings.
    var red: Double {
      get { outputSettings.red }
      set { outputSettings.red = newValue }
    }

    /// The green component of the color to apply, kept in the output settings.
    var green: Double {
      get { outputSettings.green }
      set { outputSettings.green = newValue }
    }

    /// The blue component of the color to apply, kept in the output settings.
    var blue: Double {
      get { outputSettings.blue }
      set { outputSettings.blue = newValue }
    }

    /// The brightness to apply, kept in the output settings.
    var brightness: Double {
      get { outputSettings.brightness }
      set { outputSettings.brightness = newValue }
    }

    /// What the selected controller can do as output; none without a controller.
    var capabilities: PhysicalControllerOutputCapabilities {
      device?.physicalOutputCapabilities ?? .none
    }

    /// What the live view draws for the selected controller.
    var controlLayout: InputTestControlLayout {
      InputTestControlLayout(
        capabilities: device?.capabilities ?? ControllerCapabilities(controls: [])
      )
    }

    /// The sections shown for the selected controller: Motion calibration needs a gyroscope and
    /// Lighting needs a lighting feature; Rumble states when the controller has no motor.
    var visibleSections: [InputTestSection] {
      InputTestSection.allCases.filter { section in
        switch section {
        case .liveInput, .rumble: true
        case .motion: device?.capabilities.motion == true
        case .lighting: !capabilities.lightingFeatures.isEmpty
        }
      }
    }

    /// The rumble test lengths in milliseconds, up to the longest the service accepts, which
    /// `ojd controller rumble --duration` also allows.
    static let rumbleDurationRange = 100...maxRumbleDurationMs

    /// Returns the length in milliseconds, rounded and clamped to ``rumbleDurationRange``.
    ///
    /// - Parameter milliseconds: The length the slider holds.
    /// - Returns: The length in milliseconds, rounded and clamped to ``rumbleDurationRange``.
    static func clampedRumbleDuration(_ milliseconds: Double) -> Int {
      max(
        rumbleDurationRange.lowerBound,
        min(rumbleDurationRange.upperBound, Int(milliseconds.rounded()))
      )
    }

    /// The latest input of the controller.
    var latestInput: ControllerState { liveState.snapshot }

    /// Whether the input is being sampled.
    var isSampling: Bool { samplingTask != nil }

    /// Whether an output test runs.
    var isOutputBusy: Bool {
      if case .running = outputState { return true }
      return false
    }

    /// Whether the controller is connected, so an output can be sent.
    var canSendOutput: Bool { isDeviceConnected && device != nil }
    /// Whether the running output test is a rumble that Stop can end.
    var canStopRumble: Bool { outputMayRequireRumbleStop }
  }

#endif
