#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  struct ProfileListButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
      configuration.label.foregroundColor(Color.primary).background(
        RoundedRectangle(cornerRadius: 6).fill(
          selected ? Color(NSColor.selectedControlColor).opacity(0.42) : Color.clear
        )
      ).opacity(configuration.isPressed ? 0.72 : 1)
    }
  }

  /// A destructive action that keeps the native semantic role on systems that support it while
  /// retaining a visibly destructive fallback for the macOS 10.15 deployment target.
  struct OJDDestructiveButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
      self.action = action
      self.label = label
    }

    @ViewBuilder var body: some View {
      if #available(macOS 12.0, *) {
        Button(role: .destructive, action: action, label: label).foregroundColor(
          Color(NSColor.systemRed)
        )
      } else {
        Button(action: action, label: label).foregroundColor(Color(NSColor.systemRed))
      }
    }
  }

  extension View {
    /// SwiftUI's tooltip modifier was introduced after the app's minimum deployment target.
    @ViewBuilder func ojdHelp(_ message: String) -> some View {
      if #available(macOS 11.0, *) { help(message) } else { self }
    }
  }

  struct ProfileActionErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
      HStack(alignment: .top, spacing: 10) {
        OJDSystemSymbol(name: "exclamationmark.triangle", fallback: "!").foregroundColor(
          Color(NSColor.systemRed)
        )
        VStack(alignment: .leading, spacing: 4) {
          Text("Profile action needs attention").font(.headline)
          Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        Spacer(minLength: 0)
        Button("Dismiss", action: dismiss)
      }.padding(12).background(Color(NSColor.controlBackgroundColor)).ojdAccessibilityLabel(
        "Profile action error"
      ).ojdAccessibilityValue(message)
    }
  }

#endif
