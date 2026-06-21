import SwiftUI

struct RumbleSlider: View {
  let label: String
  @Binding var value: Double

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .frame(width: 34, alignment: .leading)
      Slider(value: $value, in: 0...255, step: 1)
        .frame(width: 116)
      Text("\(Int(value))")
        .font(.system(.caption, design: .monospaced))
        .frame(width: 30, alignment: .trailing)
    }
    .accessibilityElement(children: .combine)
  }
}
