#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct MotionCalibrationControls: View {
    @ObservedObject var model: MotionCalibrationViewModel

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text(OJDLocalized.string(
            "motion.calibration.instructions",
            fallback: "Keep the controller still while collecting gyro bias."
          )).font(.caption).fixedSize(horizontal: false, vertical: true)
          if let status = model.status {
            if !status.hasMotionBaseline {
              Text(OJDLocalized.string(
                "motion.calibration.waiting",
                fallback: "Waiting for motion samples. Refresh to check again."
              )).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Text(status.isCollecting
              ? OJDLocalized.string("motion.calibration.collecting", fallback: "Collecting bias")
              : OJDLocalized.string(
                "motion.calibration.paused", fallback: "Manual collection paused"
              )
            )
            Text(OJDLocalized.formatted(
              "motion.calibration.offset",
              fallback: "Bias (°/s): X %.3f · Y %.3f · Z %.3f",
              status.offsetDegreesPerSecond.x,
              status.offsetDegreesPerSecond.y,
              status.offsetDegreesPerSecond.z
            )).font(.caption).fixedSize(horizontal: false, vertical: true)
            if status.isCollecting {
              Text(OJDLocalized.string(
                "motion.calibration.continues",
                fallback: "Collection continues when this window closes. Use Pause to stop it."
              )).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
          }
          if let error = model.errorMessage {
            Text(error).font(.caption).foregroundColor(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
          HStack {
            Button(OJDLocalized.string("common.refresh", fallback: "Refresh")) {
              Task { await model.refresh() }
            }
            if model.isBusy { OJDLoadingIndicator() }
          }
          HStack {
            Button(OJDLocalized.string("motion.calibration.start", fallback: "Start calibration")) {
              Task { await model.perform(.start) }
            }.disabled(
              model.status?.hasMotionBaseline != true || model.status?.isCollecting == true
            )
            Button(OJDLocalized.string("motion.calibration.pause", fallback: "Pause")) {
              Task { await model.perform(.pause) }
            }.disabled(model.status?.isCollecting != true)
            Button(OJDLocalized.string("common.reset", fallback: "Reset")) {
              Task { await model.perform(.reset) }
            }.disabled(model.status == nil)
          }
        }.disabled(model.selector == nil || model.isBusy)
      } label: {
        Text(OJDLocalized.string("motion.calibration.title", fallback: "Motion calibration"))
      }
    }
  }
#endif
