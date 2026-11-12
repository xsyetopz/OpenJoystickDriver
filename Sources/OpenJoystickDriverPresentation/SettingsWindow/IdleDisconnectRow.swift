#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The row of the General pane that sets how long a Bluetooth controller may have no changed
  /// input before it disconnects.
  struct IdleDisconnectRow: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel

    private static let choices = [5, 10, 15, 30, 60]

    var body: some View {
      HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.small) {
        VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
          Text(OJDLocalized.string("ui.settings.general.idleDisconnect"))
          Text(OJDLocalized.string("ui.settings.general.idleDisconnectDescription")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 8)
        Picker(
          OJDLocalized.string("ui.settings.general.idleDisconnect"),
          selection: Binding(
            get: { preferences.idleDisconnectMinutes },
            set: { preferences.setIdleDisconnectMinutes($0) }
          )
        ) {
          Text(OJDLocalized.string("ui.settings.general.idleDisconnectOff")).tag(Int?.none)
          ForEach(options, id: \.self) { minutes in
            Text(OJDLocalized.plural("ui.settings.general.idleDisconnectMinutes", count: minutes))
              .tag(Int?.some(minutes))
          }
        }.labelsHidden().fixedSize()
      }
    }

    /// The preset choices, plus a value the CLI stored that no preset names.
    private var options: [Int] {
      guard let current = preferences.idleDisconnectMinutes, !Self.choices.contains(current)
      else { return Self.choices }
      return (Self.choices + [current]).sorted()
    }
  }

#endif
