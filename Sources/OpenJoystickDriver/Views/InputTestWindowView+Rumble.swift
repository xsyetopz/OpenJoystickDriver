import OpenJoystickDriverKit
import SwiftUI

extension InputTestWindowView {
  func outputTestRow(_ device: DeviceViewModel) -> some View {
    let canRumble = device.supportsPhysicalRumble
    return OJDCard(title: L10n.string("input.rumbleTest")) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(
            canRumble
              ? L10n.string("input.rumbleSendShort") : L10n.string("input.rumbleUnavailable")
          ).font(.caption).foregroundColor(.secondary)
          Spacer()
          Text(canRumble ? L10n.string("input.supported") : L10n.string("input.unavailable")).font(
            .system(size: 10, weight: .semibold)
          ).foregroundColor(canRumble ? .green : .secondary)
        }
        VStack(alignment: .leading, spacing: 7) {
          Text(L10n.string("input.motors")).font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
          HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
              RumbleSlider(label: L10n.string("input.left"), value: $rumbleLeft)
              RumbleSlider(label: L10n.string("input.right"), value: $rumbleRight)
            }
            VStack(alignment: .leading, spacing: 5) {
              RumbleSlider(label: "LT", value: $rumbleLT)
              RumbleSlider(label: "RT", value: $rumbleRT)
            }
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            rumbleIconButton(
              rumbleRunning ? L10n.string("input.sending") : L10n.string("input.pulse"),
              systemName: rumbleRunning ? "hourglass" : "dot.radiowaves.left.and.right"
            ) { sendRumble(to: device, durationMs: Int(rumbleDurationMs)) }.disabled(
              rumbleRunning || !canRumble
            )
            rumbleIconButton(L10n.string("input.hold"), systemName: "infinity") {
              sendRumble(to: device, durationMs: 0)
            }.disabled(!canRumble)
            rumbleIconButton(L10n.string("input.stop"), systemName: "stop.fill") {
              sendRumble(to: device, left: 0, right: 0, lt: 0, rt: 0, durationMs: 0)
            }.disabled(!canRumble)
            Divider().frame(height: 18)
            Stepper(
              L10n.string("input.durationMs", Int(rumbleDurationMs)),
              value: $rumbleDurationMs,
              in: 50...5000,
              step: 50
            ).font(.caption).frame(width: 160)
          }
          HStack(spacing: 8) {
            rumbleIconButton(L10n.string("input.leftMotor"), systemName: "l.circle") {
              sendRumble(to: device, left: UInt8(clamping: Int(rumbleLeft)), right: 0, lt: 0, rt: 0)
            }.disabled(rumbleRunning || !canRumble)
            rumbleIconButton(L10n.string("input.rightMotor"), systemName: "r.circle") {
              sendRumble(
                to: device,
                left: 0,
                right: UInt8(clamping: Int(rumbleRight)),
                lt: 0,
                rt: 0
              )
            }.disabled(rumbleRunning || !canRumble)
            Divider().frame(height: 16)
            rumbleIconButton(L10n.string("input.low"), systemName: "speaker.wave.1.fill") {
              setRumbleValues(left: 32, right: 32, lt: 32, rt: 32)
            }
            rumbleIconButton(L10n.string("input.mid"), systemName: "speaker.wave.2.fill") {
              setRumbleValues(left: 128, right: 128, lt: 128, rt: 128)
            }
            rumbleIconButton(L10n.string("input.max"), systemName: "speaker.wave.3.fill") {
              setRumbleValues(left: 255, right: 255, lt: 255, rt: 255)
            }
            rumbleIconButton(L10n.string("input.zero"), systemName: "speaker.slash.fill") {
              setRumbleValues(left: 0, right: 0, lt: 0, rt: 0)
            }
          }
          HStack(spacing: 8) {
            if let rumbleResult {
              Text(L10n.string("input.lastCommand", rumbleResult)).font(.caption).foregroundColor(
                .secondary
              )
            } else {
              Text(L10n.string("input.rumblePhysicalOnly")).font(.caption).foregroundColor(
                .secondary
              )
            }
          }
        }
      }
    }
  }

  @ViewBuilder func rumbleIconButton(
    _ title: String,
    systemName: String,
    action: @escaping () -> Void
  ) -> some View {
    SwiftUI.Button(action: action) {
      if #available(macOS 11.0, *) {
        VStack(spacing: 3) {
          Image(systemName: systemName).font(.system(size: 14, weight: .semibold))
          Text(rumbleGlyphCaption(title)).font(.system(size: 9, weight: .medium)).lineLimit(1)
        }.frame(width: 44, height: 36).contentShape(RoundedRectangle(cornerRadius: 7))
          .accessibilityElement(children: .ignore).accessibilityLabel(Text(title))
      } else {
        Text(title).font(.caption).frame(width: 44, height: 36)
      }
    }.buttonStyle(.borderless)
  }

  func rumbleGlyphCaption(_ title: String) -> String {
    if title == L10n.string("input.sending") { return "sending" }
    if title == L10n.string("input.pulse") { return "pulse" }
    if title == L10n.string("input.hold") { return "hold" }
    if title == L10n.string("input.stop") { return "stop" }
    if title == L10n.string("input.leftMotor") { return "L" }
    if title == L10n.string("input.rightMotor") { return "R" }
    if title == L10n.string("input.low") { return "low" }
    if title == L10n.string("input.mid") { return "mid" }
    if title == L10n.string("input.max") { return "max" }
    if title == L10n.string("input.zero") { return "zero" }
    return title
  }

  func sendRumble(
    to device: DeviceViewModel,
    left: UInt8? = nil,
    right: UInt8? = nil,
    lt: UInt8? = nil,
    rt: UInt8? = nil,
    durationMs: Int? = nil
  ) {
    rumbleRunning = true
    rumbleResult = nil
    Task {
      let ok = await model.sendPhysicalRumble(
        vendorID: device.vendorID,
        productID: device.productID,
        left: left ?? UInt8(clamping: Int(rumbleLeft)),
        right: right ?? UInt8(clamping: Int(rumbleRight)),
        lt: lt ?? UInt8(clamping: Int(rumbleLT)),
        rt: rt ?? UInt8(clamping: Int(rumbleRT)),
        durationMs: durationMs ?? Int(rumbleDurationMs)
      )
      rumbleResult = ok ? L10n.string("input.rumbleSent") : L10n.string("input.rumbleNotAvailable")
      rumbleRunning = false
    }
  }

  func setRumbleValues(left: Double, right: Double, lt: Double, rt: Double) {
    rumbleLeft = left
    rumbleRight = right
    rumbleLT = lt
    rumbleRT = rt
  }
}
