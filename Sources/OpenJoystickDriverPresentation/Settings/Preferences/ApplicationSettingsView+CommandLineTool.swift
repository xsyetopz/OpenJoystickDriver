#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import SwiftUI

  extension ApplicationSettingsView {
    var commandLineToolSettings: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 12) {
            Text(commandLineToolStatus).font(.caption).foregroundColor(
              Color(NSColor.secondaryLabelColor)
            ).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            switch commandLineTool.state {
            case .installed:
              Button(
                OJDLocalized.string("settings.commandLineTool.uninstall", fallback: "Uninstall")
              ) { commandLineTool.uninstall() }
            case .notInstalled, .linkedElsewhere:
              Button(
                OJDLocalized.string(
                  "settings.commandLineTool.install",
                  fallback: "Install Command-Line Tool"
                )
              ) { commandLineTool.install() }
            case .blockedByFile: EmptyView()
            }
          }
          if let message = commandLineTool.errorMessage {
            Text(message).font(.caption).foregroundColor(Color(NSColor.systemOrange)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }
        }.padding(4).frame(maxWidth: .infinity, alignment: .topLeading)
      } label: {
        Text(OJDLocalized.string("settings.commandLineTool", fallback: "Command-Line Tool")).font(
          .headline
        )
      }.onAppear { commandLineTool.refresh() }
    }

    private var commandLineToolStatus: String {
      let path = commandLineTool.link.linkURL.path
      switch commandLineTool.state {
      case .notInstalled:
        return OJDLocalized.formatted(
          "settings.commandLineTool.notInstalled",
          fallback: "Links %@ to this app so you can run ojd in Terminal. macOS asks for an "
            + "administrator password.",
          path
        )
      case .installed:
        return OJDLocalized.formatted(
          "settings.commandLineTool.installed",
          fallback: "Installed. Run ojd in Terminal; uninstalling removes %@.",
          path
        )
      case .linkedElsewhere(let destination):
        return OJDLocalized.formatted(
          "settings.commandLineTool.linkedElsewhere",
          fallback: "%@ points to %@. Installing links it to this app instead.",
          path,
          destination
        )
      case .blockedByFile:
        return OJDLocalized.formatted(
          "settings.commandLineTool.blocked",
          fallback: "%@ is a file, not a link. Remove it, then install again.",
          path
        )
      }
    }
  }

#endif
