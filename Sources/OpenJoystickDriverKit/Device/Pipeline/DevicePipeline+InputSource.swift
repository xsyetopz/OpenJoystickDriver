import Foundation

/// The physical-controller path: the pipeline reads and parses a controller's reports and sends
/// the frames to the dispatcher it was built with.
extension DevicePipeline: InputSource {
  /// The origin of the frames of this pipeline: a physical controller.
  nonisolated var origin: InputOrigin { .physicalController }
  /// The dispatcher that receives the frames.
  nonisolated var sink: any OutputSink { dispatcher }
}
