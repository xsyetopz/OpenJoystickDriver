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
                OJDLocalized.string("settings.commandLineTool.uninstall")
              ) { commandLineTool.uninstall() }
            case .notInstalled, .linkedElsewhere:
              Button(
                OJDLocalized.string(
                  "settings.commandLineTool.install"
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
        Text(OJDLocalized.string("settings.commandLineTool")).font(
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
          path
        )
      case .installed:
        return OJDLocalized.formatted(
          "settings.commandLineTool.installed",
          path
        )
      case .linkedElsewhere(let destination):
        return OJDLocalized.formatted(
          "settings.commandLineTool.linkedElsewhere",
          path,
          destination
        )
      case .blockedByFile:
        return OJDLocalized.formatted(
          "settings.commandLineTool.blocked",
          path
        )
      }
    }
  }

#endif
