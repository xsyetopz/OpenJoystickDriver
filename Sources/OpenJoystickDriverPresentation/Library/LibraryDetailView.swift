#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The detail column of the Library: everything `ojd record show` and `ojd mod list` print
  /// for the selected record or mod.
  struct LibraryDetailView: View {
    /// The model of the app's view of the service, refreshed after a confirmed change.
    @ObservedObject
    var runtime: RuntimeViewModel
    /// The model of the Library area.
    @ObservedObject
    var model: LibraryViewModel

    /// The detail content with the sheet that confirms a pending change.
    var body: some View {
      content.sheet(item: $model.pending) { pending in
        LibraryConfirmationSheet(
          confirmation: pending.confirmation,
          cancel: { model.cancelPending() },
          confirm: {
            if model.confirmPending() { Task { @MainActor in await runtime.refresh() } }
          }
        )
      }
    }

    /// The detail of the selected record or mod, or the empty state when nothing is selected.
    @ViewBuilder
    private var content: some View {
      if let detail = model.recordDetail {
        Form {
          feedback
          recordSections(detail)
        }.ojdGroupedForm()
      } else if let mod = model.selectedMod {
        Form {
          feedback
          modSections(mod)
        }.ojdGroupedForm()
      } else {
        ZStack {
          EmptyStateView(
            symbol: "books.vertical",
            title: OJDLocalized.string("ui.library.detail.empty")
          )
          if model.failure != nil || model.notice != nil {
            VStack(spacing: OJDSpacing.none) {
              Form { feedback }.ojdGroupedForm().fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
            }
          }
        }
      }
    }

    /// The inline error and the notice of the latest operation, each with a Dismiss button.
    @ViewBuilder
    private var feedback: some View {
      if model.failure != nil || model.notice != nil {
        Section {
          if let failure = model.failure {
            InlineErrorView(
              message: failure.message,
              code: failure.code,
              detailsTitle: OJDLocalized.string("ui.library.details"),
              detailsAccessibilityLabel: OJDLocalized.string("a11y.library.details"),
              actionTitle: OJDLocalized.string("ui.library.dismiss"),
              actionAccessibilityLabel: OJDLocalized.string("a11y.library.dismissError")
            ) { model.dismissFailure() }
          }
          if let notice = model.notice {
            HStack(alignment: .firstTextBaseline) {
              OJDSystemSymbol(
                name: SemanticState.healthy.presentation.symbolName,
                fallback: OJDLocalized.string("term.status")
              ).foregroundColor(Color(SemanticState.healthy.presentation.tone.color))
                .accessibilityHidden(true)
              Text(notice).fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
              Button(OJDLocalized.string("ui.library.dismiss")) { model.dismissNotice() }
                .ojdAccessibilityLabel(OJDLocalized.string("a11y.library.dismissNotice"))
            }.accessibilityElement(children: .contain).ojdAccessibilityLabel(notice)
          }
        }
      }
    }

    // MARK: Record

    /// The sections of a record: its identity and source, a test result when there is one, its
    /// fields and layers, and its JSON.
    @ViewBuilder
    private func recordSections(_ detail: LibraryRecordDetail) -> some View {
      Section {
        OJDLabeledValue(OJDLocalized.string("ui.library.field.identity"), detail.item.identity)
        OJDLabeledValue(OJDLocalized.string("ui.library.field.file"), detail.item.fileDisplayPath)
        OJDLabeledValue(OJDLocalized.string("ui.library.field.transport"), detail.transport)
        if let claimed = detail.claimedByUSBExtension {
          OJDLabeledValue(
            OJDLocalized.string("ui.library.field.usbClaim"),
            OJDLocalized.string(claimed ? "ui.library.claim.claimed" : "ui.library.claim.unclaimed")
          )
        }
        ForEach(detail.notes, id: \.self) { note in
          Text(note).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      if let run = model.testRun, run.model == detail.item.model { testSection(run) }
      if !detail.fields.isEmpty {
        Section(header: Text(OJDLocalized.string("ui.library.section.fields"))) {
          ForEach(detail.fields) { field in
            if field.layer == detail.item.layer {
              Text(field.name)
            } else {
              OJDLabeledValue(field.name, field.layer.libraryTitle)
            }
          }
        }
      }
      Section { recordDocument(detail) }
    }

    /// The Record section: the record JSON, or a line that says the text cannot be shown.
    @ViewBuilder
    private func recordDocument(_ detail: LibraryRecordDetail) -> some View {
      switch detail.record {
      case .text(let text):
        LibraryRecordTextView(text: text)
      case .unreadable:
        Text(OJDLocalized.formatted("ui.library.recordUnreadable", detail.item.identity))
          .foregroundColor(Color(SemanticTone.attention.color))
      }
    }

    /// The Test Result section: whether the capture matched the expectation, with each difference.
    private func testSection(_ run: LibraryTestRun) -> some View {
      Section(header: Text(OJDLocalized.string("ui.library.section.testResult"))) {
        if run.result.matches {
          Text(
            OJDLocalized.plural(
              "cli.record.test.matched",
              run.model.description,
              run.result.inputReports
            )
          )
        } else {
          Text(
            OJDLocalized.plural(
              "cli.record.test.mismatch",
              run.model.description,
              run.expectation,
              run.result.differences.count
            )
          )
          ForEach(run.result.differences, id: \.field) { difference in
            Text(
              OJDLocalized.formatted(
                "cli.record.test.difference",
                difference.field,
                difference.expected,
                difference.actual
              )
            ).textSelection(.enabled)
          }
        }
      }
    }

    // MARK: Mod

    /// The sections of a mod: its name, version, author and problem, and its files.
    @ViewBuilder
    private func modSections(_ mod: LibraryModItem) -> some View {
      Section {
        if let version = mod.version {
          OJDLabeledValue(OJDLocalized.string("ui.library.field.version"), version)
        }
        if let author = mod.author {
          OJDLabeledValue(OJDLocalized.string("ui.library.field.author"), author)
        }
        if let problem = mod.problem {
          Text(OJDLocalized.formatted("ui.library.mod.unused", problem))
            .foregroundColor(Color(SemanticTone.caution.color))
        }
      }
      if !mod.files.isEmpty {
        Section(header: Text(OJDLocalized.string("ui.library.section.files"))) {
          ForEach(mod.files, id: \.self) { file in Text(file).textSelection(.enabled) }
        }
      }
    }
  }

#endif
