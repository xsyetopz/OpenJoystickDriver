#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  /// The Library area: the controller records and mod packages that `ojd record` and `ojd mod`
  /// manage.
  ///
  /// The list column holds the records and mods; the detail column shows the selected one in full.
  struct LibraryAreaView: View {
    /// The model of the app's view of the service.
    @ObservedObject
    var runtime: RuntimeViewModel
    /// The model of the Library area.
    @ObservedObject
    var model: LibraryViewModel

    /// The column of the main window that this view fills.
    let column: MainWindowColumn

    /// The list or the detail column of the Library area.
    @ViewBuilder
    var body: some View {
      switch column {
      case .list: LibraryListView(model: model).ojdInterfaceRow(LibraryRow.list)
      case .detail:
        VStack(spacing: OJDSpacing.none) {
          HiddenChangeNotice(content: .needsAdvanced).padding(.horizontal, OJDSpacing.medium)
          LibraryDetailView(runtime: runtime, model: model).ojdInterfaceRow(LibraryRow.detail)
        }
      }
    }
  }

  /// The list column of the Library: the Installed and Built-in switch, and the records and
  /// mods that match the search field.
  struct LibraryListView: View {
    /// The model of the Library area.
    @ObservedObject
    var model: LibraryViewModel

    /// The scope picker above the record list.
    var body: some View {
      VStack(spacing: OJDSpacing.none) {
        Picker(OJDLocalized.string("ui.library.records"), selection: $model.scope) {
          ForEach(LibraryScope.allCases) { scope in
            Text(OJDLocalized.string(scope.titleKey)).tag(scope)
          }
        }.pickerStyle(SegmentedPickerStyle()).labelsHidden().padding(.horizontal, 16)
          .padding(.vertical, 12).ojdInterfaceRow(LibraryRow.scopeSwitch)
        List(selection: selection) {
          Section(header: recordsHeader) {
            if model.visibleRecords.isEmpty, isSearching || model.records.skipped.isEmpty {
              emptyLine(
                isSearching ? "ui.library.search.noMatches" : "ui.library.records.empty.title"
              )
            }
            ForEach(model.visibleRecords) { item in recordRow(item) }
            if model.scope == .installed, !isSearching {
              ForEach(model.records.skipped) { skipped in skippedRow(skipped) }
            }
          }
          if model.scope == .installed {
            Section(header: Text(OJDLocalized.string("ui.library.mods"))) {
              if model.visibleMods.isEmpty {
                emptyLine(
                  isSearching ? "ui.library.search.noMatches" : "ui.library.mods.empty.title"
                )
              }
              ForEach(model.visibleMods) { mod in modRow(mod) }
            }
          }
        }.listStyle(InsetListStyle())
      }.onAppear { model.reload() }
    }

    /// Whether the search field holds text other than spaces.
    private var isSearching: Bool {
      !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The selected row, which reads and sets the selection of ``model``.
    private var selection: Binding<LibrarySelection?> {
      Binding(get: { model.selection }, set: { model.select($0) })
    }

    /// The header of the records section; the Built-in scope shows the number of records beside
    /// the title.
    @ViewBuilder
    private var recordsHeader: some View {
      switch model.scope {
      case .installed: Text(OJDLocalized.string("ui.library.records"))
      case .builtIn:
        HStack {
          Text(OJDLocalized.string("ui.library.builtIn"))
          Spacer()
          Text(model.records.builtIn.count.formatted())
        }.ojdAccessibilityValue(model.records.builtIn.count.formatted())
      }
    }

    /// A secondary-colored line for an empty list, with the text of `key`.
    private func emptyLine(_ key: String) -> some View {
      Text(OJDLocalized.string(key)).foregroundColor(.secondary)
    }

    /// The row of a record: its identity, then its family and layer, and the file that patches it.
    private func recordRow(_ item: LibraryRecordItem) -> some View {
      let summary = OJDLocalized.formatted(
        "ui.library.record.detail",
        item.family.displayName,
        item.layer.libraryTitle
      )
      return VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
        Text(item.identity)
        Text(summary).font(.caption).foregroundColor(.secondary)
        if let patch = item.patchedBy {
          Text(OJDLocalized.formatted("ui.library.record.patchedBy", patch)).font(.caption)
            .foregroundColor(.secondary)
        }
      }.tag(LibrarySelection.record(item.model)).ojdAccessibilityLabel(item.identity)
        .ojdAccessibilityValue(summary)
    }

    /// The row of a file that OJD skipped, with its path and the problem.
    private func skippedRow(_ skipped: LibrarySkippedFile) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
        Text(skipped.displayPath)
        Text(OJDLocalized.formatted("ui.library.record.skipped", skipped.problem)).font(.caption)
          .foregroundColor(.secondary)
      }.ojdAccessibilityLabel(skipped.path).ojdAccessibilityValue(skipped.problem)
    }

    /// The row of a mod: its name, then its version and author.
    private func modRow(_ mod: LibraryModItem) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
        Text(mod.name)
        if let summary = mod.summary {
          Text(summary).font(.caption).foregroundColor(.secondary)
        }
      }.tag(LibrarySelection.mod(mod.name)).ojdAccessibilityLabel(mod.name)
        .ojdAccessibilityValue(mod.summary ?? "")
    }
  }

  extension LibraryModItem {
    /// The version and author in one line; nil when the package names neither.
    var summary: String? {
      switch (version, author) {
      case (let version?, let author?):
        return OJDLocalized.formatted("ui.library.mod.detail", version, author)
      case (let single?, nil), (nil, let single?): return single
      case (nil, nil): return nil
      }
    }
  }

  /// The sheet that asks the person to confirm installing, replacing or removing a record or mod.
  struct LibraryConfirmationSheet: View {
    /// The text and button of the sheet.
    let confirmation: LibraryConfirmation
    /// The action of the Cancel button.
    let cancel: () -> Void
    /// The action of the confirming button.
    let confirm: () -> Void

    /// The title, the message and the Cancel and confirm buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Text(confirmation.title).font(.headline).fixedSize(horizontal: false, vertical: true)
        Text(confirmation.message).foregroundColor(Color(NSColor.secondaryLabelColor))
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel"), action: cancel).keyboardShortcut(
            .cancelAction
          ).ojdAccessibilityLabel(OJDLocalized.string("a11y.library.cancel"))
          Button(confirmation.confirmTitle, action: confirm).keyboardShortcut(.defaultAction)
            .ojdAccessibilityLabel(confirmation.confirmTitle)
        }
      }.ojdSheet(.compact)
    }
  }

  /// Opens the file panels of the Library area.
  @MainActor
  enum LibraryFilePicker {
    /// Asks the person to choose a record file or a mod folder.
    ///
    /// Returns its URL, or nil when the person cancels.
    static func chooseRecordOrModFolder() -> URL? {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.propertyList, .folder]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = true
      panel.message = OJDLocalized.string("ui.library.recordOrMod.pick")
      panel.prompt = OJDLocalized.string("ui.library.choose")
      return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks the person to choose a packet capture, which is JSON lines that no content type names.
    ///
    /// Returns its URL, or nil when the person cancels.
    static func chooseCapture() -> URL? {
      chooseFile(message: "ui.library.test.packets.pick")
    }

    /// Asks the person to choose an expectation file.
    ///
    /// Returns its URL, or nil when the person cancels.
    static func chooseExpectation() -> URL? {
      chooseFile(message: "ui.library.test.expect.pick", type: .json)
    }

    /// Asks the person to choose one file.
    ///
    /// - Parameters:
    ///   - message: The localization key of the text the panel shows.
    ///   - type: The content type the panel allows, or nil for any file.
    /// - Returns: The URL of the file, or nil when the person cancels.
    private static func chooseFile(message: String, type: UTType? = nil) -> URL? {
      let panel = NSOpenPanel()
      if let type { panel.allowedContentTypes = [type] }
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.message = OJDLocalized.string(message)
      panel.prompt = OJDLocalized.string("ui.library.choose")
      return panel.runModal() == .OK ? panel.url : nil
    }
  }

#endif
