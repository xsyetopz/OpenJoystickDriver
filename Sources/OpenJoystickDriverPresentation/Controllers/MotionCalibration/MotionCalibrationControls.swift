#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct MotionCalibrationControls: View {
    @ObservedObject
    var model: MotionCalibrationViewModel
    let embedded: Bool

    init(model: MotionCalibrationViewModel, embedded: Bool = false) {
      self.model = model
      self.embedded = embedded
    }

    @ViewBuilder
    var body: some View {
      if embedded {
        content
      } else {
        GroupBox {
          content
        } label: {
          Text(OJDLocalized.string("motion.calibration.title"))
        }
      }
    }

    private var content: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(
          OJDLocalized.string(
            "motion.calibration.instructions"
          )
        ).font(.caption).fixedSize(horizontal: false, vertical: true)
        if let status = model.status {
          if !status.hasMotionBaseline {
            Text(
              OJDLocalized.string(
                "motion.calibration.waiting"
              )
            ).font(.caption).fixedSize(horizontal: false, vertical: true)
          }
          Text(
            status.isCollecting
              ? OJDLocalized.string("motion.calibration.collecting")
              : OJDLocalized.string(
                "motion.calibration.paused"
              )
          )
          Text(
            OJDLocalized.formatted(
              "motion.calibration.offset",
              status.offsetDegreesPerSecond.x,
              status.offsetDegreesPerSecond.y,
              status.offsetDegreesPerSecond.z
            )
          ).font(.caption).fixedSize(horizontal: false, vertical: true)
          if status.isCollecting {
            Text(
              OJDLocalized.string(
                "motion.calibration.continues"
              )
            ).font(.caption).fixedSize(horizontal: false, vertical: true)
          }
        }
        if let error = model.errorMessage {
          Text(error).font(.caption).foregroundColor(.red).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack {
          Button(OJDLocalized.string("common.refresh")) {
            Task { await model.refresh() }
          }
          if model.isBusy { ProgressView() }
        }
        HStack {
          Button(OJDLocalized.string("motion.calibration.start")) {
            Task { await model.perform(.start) }
          }.disabled(model.status?.hasMotionBaseline != true || model.status?.isCollecting == true)
          Button(OJDLocalized.string("motion.calibration.pause")) {
            Task { await model.perform(.pause) }
          }.disabled(model.status?.isCollecting != true)
          Button(OJDLocalized.string("common.reset")) {
            Task { await model.perform(.reset) }
          }.disabled(model.status == nil)
        }
      }.disabled(model.selector == nil || model.isBusy)
    }
  }
#endif
