#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The row of the General pane that shows the pause shortcut and records a new one.
  ///
  /// While it records, the next key press with a modifier becomes the shortcut and Escape ends the
  /// recording.
  struct PauseShortcutRow: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel
    @State
    private var isRecording = false
    @State
    private var monitor: Any?

    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
        controls
        SettingsBesideError(preferences: preferences, origin: .pauseShortcut)
      }
    }

    private var controls: some View {
      HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.small) {
        VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
          Text(OJDLocalized.string("ui.settings.general.pauseShortcut"))
          Text(OJDLocalized.string("ui.settings.general.pauseShortcutDescription")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 8)
        Text(
          preferences.pauseShortcut.map(PauseShortcutDisplay.text)
            ?? OJDLocalized.string("status.notSet")
        )
        .foregroundColor(Color(NSColor.secondaryLabelColor))
        Button(
          isRecording
            ? OJDLocalized.string("ui.settings.general.pauseShortcutRecording")
            : OJDLocalized.string("ui.settings.general.pauseShortcutRecord")
        ) { startRecording() }.disabled(isRecording)
          .help(OJDLocalized.string("ui.help.recordPauseShortcut"))
        Button(OJDLocalized.string("action.clear")) { preferences.setPauseShortcut(nil) }
          .disabled(preferences.pauseShortcut == nil)
          .help(OJDLocalized.string("ui.help.clearPauseShortcut"))
      }.onDisappear { stopRecording() }
    }

    private func startRecording() {
      isRecording = true
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode != 53 {
          preferences.recordPauseShortcut(
            code: UInt32(event.keyCode),
            modifiers: Self.modifiers(of: event)
          )
        }
        stopRecording()
        return nil
      }
    }

    private func stopRecording() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      isRecording = false
    }

    /// The modifier keys held in `event`.
    private static func modifiers(of event: NSEvent) -> Set<PauseShortcut.Modifier> {
      let flags = event.modifierFlags
      return Set(
        [
          (NSEvent.ModifierFlags.command, PauseShortcut.Modifier.command),
          (.control, .control), (.option, .option), (.shift, .shift),
        ].filter { flags.contains($0.0) }.map(\.1)
      )
    }
  }

#endif
