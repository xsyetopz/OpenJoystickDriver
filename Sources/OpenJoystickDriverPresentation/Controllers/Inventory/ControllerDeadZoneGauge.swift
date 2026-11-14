#if canImport(SwiftUI)

  import SwiftUI

  /// A bar of a stick or trigger from rest to full, with the dead zone as a shaded span from rest,
  /// the raw value as a line, and the value after tuning as a filled span.
  struct ControllerDeadZoneGauge: View {
    /// The height of the bar.
    private static let height: CGFloat = 8

    /// The row the bar draws.
    let row: ControllerCalibrationRow

    /// The bar.
    var body: some View {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Rectangle().fill(Color.secondary.opacity(0.15))
          Rectangle().fill(Color.accentColor.opacity(0.6))
            .frame(width: (row.tuned ?? 0) * proxy.size.width)
          if let end = Self.deadZoneEnd(of: row, width: proxy.size.width) {
            Rectangle().fill(Color.orange.opacity(0.5)).frame(width: end)
          }
          Rectangle().fill(Color.primary).frame(width: 2)
            .offset(x: row.raw * proxy.size.width - 1)
        }.clipped()
      }.frame(height: Self.height).accessibilityHidden(true)
    }

    /// The width of the dead zone in a bar `width` wide; nil for a row with no dead zone.
    nonisolated static func deadZoneEnd(
      of row: ControllerCalibrationRow,
      width: Double
    ) -> Double? {
      row.deadZone.map { $0 * width }
    }
  }

#endif
