/// Discovery route that owns a connected controller pipeline.
public enum DeviceDiscoverySource: String, Codable, Sendable {
  case hid
  case rawUSB
}
