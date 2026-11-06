import Foundation
import IOKit
import OpenJoystickDriverKit

/// The facts that the registry shows about a device.
public struct PassiveUSBObservedUSBFacts: Equatable, Sendable, Codable {
  /// The vendor and product ID pair of the device.
  public let tuple: PassiveUSBDescriptorTuple
  /// The device name.
  public let name: String?
  /// Raw USB `bcdDevice`; nil when the registry does not expose a 16-bit value.
  public let deviceRelease: UInt16?
  /// The device class.
  public let deviceClass: UInt8?
  /// The device subclass.
  public let deviceSubclass: UInt8?
  /// The device protocol.
  public let deviceProtocol: UInt8?
  /// The number of configurations.
  public let configurationCount: UInt8?
  /// The active configuration value.
  public let activeConfiguration: UInt8?
  /// Whether the registry shows the interfaces.
  public let interfacesState: PassiveUSBVerificationState
  /// Whether the registry shows the HID descriptor.
  public let hidDescriptorState: PassiveUSBVerificationState
  /// Whether the registry shows the HID collections.
  public let hidCollectionsState: PassiveUSBVerificationState
  /// Whether the registry shows the HID usages.
  public let hidUsagesState: PassiveUSBVerificationState
  /// Whether the registry shows the services bound to the device.
  public let serviceBindingsState: PassiveUSBVerificationState
  /// The classes of the bound services.
  public let serviceClasses: [String]
  /// The registry property that holds the descriptor blob that the probe used.
  public let descriptorBlobSource: PassiveUSBDescriptorBlobSource?
  /// Every registry property that holds a descriptor blob.
  public let descriptorBlobSources: [PassiveUSBDescriptorBlobSource]
  /// Whether a descriptor blob is available, and why or why not.
  public let descriptorBlobAvailability: PassiveUSBDescriptorBlobAvailability
  /// The speed that the registry shows.
  public let speedObservation: PassiveUSBSpeedObservation
  /// The parsed configuration descriptor, when the blob parsed.
  public let configurationDescriptor: PassiveUSBConfigurationDescriptor?
  /// Why the blob did not parse, when it did not.
  public let descriptorParseError: String?
  /// The verification state of the facts that a passive read cannot show.
  public let verification: PassiveUSBVerificationFacts
}

/// The states of the facts that the probe verifies.
public struct PassiveUSBVerificationFacts: Equatable, Sendable, Codable {
  /// Whether the registry shows the endpoints.
  public let endpointState: PassiveUSBVerificationState
  /// Whether the registry shows the HID descriptor.
  public let hidDescriptorState: PassiveUSBVerificationState
  /// Whether the registry shows the HID collections.
  public let hidCollectionsState: PassiveUSBVerificationState
  /// Whether the registry shows the HID usages.
  public let hidUsagesState: PassiveUSBVerificationState
  /// Whether a mapping is verified.
  public let mappingState: PassiveUSBVerificationState
  /// Whether input is verified.
  public let inputState: PassiveUSBVerificationState
  /// Whether output is verified.
  public let outputState: PassiveUSBVerificationState
  /// Whether reconnection is verified.
  public let reconnectState: PassiveUSBVerificationState
  /// Whether latency is verified.
  public let latencyState: PassiveUSBVerificationState
  /// Whether the consumer recognition is verified.
  public let consumerRecognitionState: PassiveUSBVerificationState
  /// Whether support is verified.
  public let supportState: PassiveUSBVerificationState

  /// Creates the facts.
  public init(
    endpointState: PassiveUSBVerificationState = .unverified,
    hidDescriptorState: PassiveUSBVerificationState = .unverified,
    hidCollectionsState: PassiveUSBVerificationState = .unverified,
    hidUsagesState: PassiveUSBVerificationState = .unverified,
    mappingState: PassiveUSBVerificationState = .unverified,
    inputState: PassiveUSBVerificationState = .unverified,
    outputState: PassiveUSBVerificationState = .unverified,
    reconnectState: PassiveUSBVerificationState = .unverified,
    latencyState: PassiveUSBVerificationState = .unverified,
    consumerRecognitionState: PassiveUSBVerificationState = .unverified,
    supportState: PassiveUSBVerificationState = .unverified
  ) {
    self.endpointState = endpointState
    self.hidDescriptorState = hidDescriptorState
    self.hidCollectionsState = hidCollectionsState
    self.hidUsagesState = hidUsagesState
    self.mappingState = mappingState
    self.inputState = inputState
    self.outputState = outputState
    self.reconnectState = reconnectState
    self.latencyState = latencyState
    self.consumerRecognitionState = consumerRecognitionState
    self.supportState = supportState
  }
}

/// What the controller record catalog says about the device.
public struct PassiveUSBCatalogInference: Equatable, Sendable, Codable {
  /// The source of the inference.
  public let source: String
  /// The record that matches.
  public let record: String
  /// The parser that the record names.
  public let parser: String
  /// The endpoint addresses that the record names, by role.
  public let endpoints: [String: UInt8]
}

/// How the descriptor matches a protocol family.
public struct PassiveUSBProtocolClassification: Equatable, Sendable, Codable {
  /// The classification status.
  public let status: String
  /// The descriptor predicates that hold.
  public let descriptorPredicates: [String]
  /// The wire protocol that the family uses.
  public let wireProtocol: String
}

/// Whether a descriptor parsed.
public enum PassiveUSBParsedDescriptorState: String, Equatable, Sendable, Codable {
  /// No descriptor blob is present.
  case absent
  /// The descriptor parsed.
  case parsed
  /// The registry holds several descriptor blobs that disagree.
  case ambiguous
  /// The descriptor did not parse.
  case malformed
}

/// The result of parsing the descriptor blob.
public struct PassiveUSBParsedDescriptorFacts: Equatable, Sendable, Codable {
  /// Whether a descriptor parsed.
  public let state: PassiveUSBParsedDescriptorState
  /// The parsed configuration, when the descriptor parsed.
  public let configuration: PassiveUSBConfigurationDescriptor?
  /// The registry properties that hold the blobs.
  public let sources: [PassiveUSBDescriptorBlobSource]
  /// Why the descriptor did not parse, when it did not.
  public let error: String?
}

/// What the USB specification says about the descriptor.
public struct PassiveUSBSpecificationInference: Equatable, Sendable, Codable {
  /// The identifiers of the specification sources.
  public let sourceIDs: [String]
  /// The claims that the sources support.
  public let claims: [String]
}

/// The polling rate that the user reports.
public struct PassiveUSBUserReportedPolling: Equatable, Sendable, Codable {
  /// Whether the polling rate is reported.
  public let state: PassiveUSBVerificationState
  /// The reports per second, when reported.
  public let reportsPerSecond: Double?
}

/// The result of one passive probe.
public struct PassiveUSBProbeResult: Equatable, Sendable, Codable {
  /// The facts that the registry shows.
  public let observedUSBFacts: PassiveUSBObservedUSBFacts
  /// The parsed descriptor.
  public let parsedDescriptorFacts: PassiveUSBParsedDescriptorFacts
  /// What the USB specification says about the descriptor.
  public let specificationInference: PassiveUSBSpecificationInference
  /// What the catalog says about the device.
  public let catalogInference: PassiveUSBCatalogInference
  /// The protocol family classification.
  public let protocolClassification: PassiveUSBProtocolClassification
  /// The polling rate that the user reports.
  public let userReportedPolling: PassiveUSBUserReportedPolling
}
