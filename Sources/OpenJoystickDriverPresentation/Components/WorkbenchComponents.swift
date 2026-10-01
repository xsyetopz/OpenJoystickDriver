#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  // SF Symbol via NSImage(systemSymbolName:), else fallback text. Pass a nil fallback for a
  // decorative glyph whose meaning is already printed beside it: fallback text in a glyph-sized
  // frame wraps into a column.
  struct OJDSystemSymbol: View {
    let name: String
    let fallback: String?
    let fallbackSymbolName: String?

    init(name: String, fallback: String?, fallbackSymbolName: String? = nil) {
      self.name = name
      self.fallback = fallback
      self.fallbackSymbolName = fallbackSymbolName
    }

    var body: some View {
      let preferredImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)
      let fallbackImage = fallbackSymbolName.flatMap {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil)
      }
      switch SystemSymbolPolicy.resolution(
        preferred: name,
        fallback: fallbackSymbolName,
        preferredIsAvailable: preferredImage != nil,
        fallbackIsAvailable: fallbackImage != nil
      ) {
      case .symbol(let resolvedName):
        if resolvedName == name, let preferredImage {
          Image(nsImage: preferredImage)
        } else if let fallbackImage {
          Image(nsImage: fallbackImage)
        }
      case .text: if let fallback { Text(fallback).font(.caption) }
      }
    }
  }

  struct OJDListGlyphSlot<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
      content.font(.system(size: 15, weight: .medium)).frame(
        width: 28,
        height: 28,
        alignment: .center
      ).accessibilityHidden(true)
    }
  }

  struct OJDCompactSymbolButton: View {
    let symbolName: String
    let fallbackSymbolName: String?
    let label: String
    let action: () -> Void

    init(
      symbolName: String,
      fallbackSymbolName: String? = nil,
      label: String,
      action: @escaping () -> Void
    ) {
      self.symbolName = symbolName
      self.fallbackSymbolName = fallbackSymbolName
      self.label = label
      self.action = action
    }

    var body: some View {
      Button(action: action) {
        OJDSystemSymbol(name: symbolName, fallback: label, fallbackSymbolName: fallbackSymbolName)
          .frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
      }.buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(label).help(label)
    }
  }

  extension View {
    func ojdAccessibilityLabel(_ label: String) -> some View { accessibilityLabel(Text(label)) }

    func ojdAccessibilityValue(_ value: String) -> some View { accessibilityValue(Text(value)) }

    @ViewBuilder
    func ojdAccessibilitySelection(_ selected: Bool) -> some View {
      let value = OJDLocalized.string(
        selected ? "common.selected" : "common.notSelected",
        fallback: selected ? "Selected" : "Not selected"
      )
      accessibilityValue(Text(value)).accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

  struct SettingsSidebar: View {
    @ObservedObject
    var navigation: SettingsNavigationModel
    let panes: [SettingsPane]

    var body: some View {
      List(selection: selection) {
        ForEach(panes) { pane in
          HStack(spacing: 8) {
            OJDSystemSymbol(name: pane.symbolName, fallback: nil).frame(width: 18)
              .accessibilityHidden(true)
            Text(pane.title)
            Spacer(minLength: 0)
          }.padding(.vertical, 3).tag(pane)
        }
      }.listStyle(SidebarListStyle()).frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
        .ojdAccessibilityLabel(
          OJDLocalized.string("settings.navigation", fallback: "Settings navigation")
        )
    }

    private var selection: Binding<SettingsPane?> {
      Binding(
        get: { navigation.selectedPane },
        set: { pane in if let pane { navigation.requestPane(pane) } }
      )
    }
  }

#endif
