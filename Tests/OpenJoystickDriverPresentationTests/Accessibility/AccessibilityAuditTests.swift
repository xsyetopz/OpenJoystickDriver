import Foundation
import Testing

/// Lists the controls in the app sources that VoiceOver cannot name.
///
/// The list must stay empty.
///
/// The audit is a text scan, so it cannot see:
/// - custom `NSView` controls that draw themselves or handle mouse events,
/// - views made tappable with `onTapGesture` instead of a control,
/// - label strings that are empty at run time,
/// - controls passed as generic parameters, except inside `InputTestSliderRow`, whose initializer
///   requires the label.
@Suite
struct AccessibilityAuditTests {
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Accessibility
    .deletingLastPathComponent()  // OpenJoystickDriverPresentationTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()

  private static let scannedDirectories = [
    "Sources/OpenJoystickDriverPresentation", "Sources/OpenJoystickDriver",
  ]

  private static func swiftFiles() throws -> [String] {
    try scannedDirectories.flatMap { directory -> [String] in
      let root = repository.appendingPathComponent(directory)
      let enumerator = try #require(
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      )
      return enumerator.compactMap { ($0 as? URL)?.path }
        .filter { $0.hasSuffix(".swift") }
        .map { String($0.dropFirst(repository.path.count + 1)) }
    }.sorted()
  }

  private static func findings() throws -> [UnlabeledControl] {
    try swiftFiles().flatMap { path -> [UnlabeledControl] in
      let source = try String(
        contentsOf: repository.appendingPathComponent(path),
        encoding: .utf8
      )
      return AccessibilityAudit.audit(source: source, path: path)
    }
  }

  @Test
  func everyControlHasAnAccessibleName() throws {
    let unlabeled = try Self.findings()
    #expect(
      unlabeled.isEmpty,
      "Unlabeled controls:\n\(unlabeled.map(\.description).joined(separator: "\n"))"
    )
  }

  @Test
  func theAuditCoversTheAppSources() throws {
    #expect(try Self.swiftFiles().count > 100)
  }

  @Test
  func aTitledButtonNeedsNoLabel() {
    let source = """
      struct V: View {
        var body: some View {
          Button("Save") {}
          Button(action: {}) { Text("Save") }
          Button { } label: { Label("Save", systemImage: "tray") }
          Toggle("On", isOn: $on)
          Toggle(isOn: $on) { Text("On") }
          Picker("Mode", selection: $mode) { Text("A") }
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }

  @Test
  func anIconOnlyControlIsListed() {
    let source = """
      struct V: View {
        var body: some View {
          Button(action: {}) { Image(systemName: "gear") }
          Button { } label: { OJDSystemSymbol(name: "gear", fallback: nil) }
          Slider(value: $value, in: 0...1)
          Picker(selection: $mode) { Text("A") }
          Toggle(isOn: $on) { Image(systemName: "gear") }
          Image(systemName: "gear")
          TextField("", text: $text)
        }
      }
      """
    let findings = AccessibilityAudit.audit(source: source, path: "V.swift")
    #expect(findings.map(\.line) == [3, 4, 5, 6, 7, 8, 9])
  }

  @Test
  func aSymbolNamesItselfUnlessItsFallbackIsALiteral() {
    let source = """
      struct V: View {
        var body: some View {
          OJDSystemSymbol(name: "gear", fallback: OJDLocalized.string("term.status"))
          OJDSystemSymbol(name: "gear", fallback: nil)
          OJDSystemSymbol(name: "arrow.right", fallback: "->")
          OJDSystemSymbol(name: "arrow.right", fallback: "->").accessibilityHidden(true)
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").map(\.line) == [5])
  }

  @Test
  func anAccessibilityLabelOrHiddenImageNamesTheControl() {
    let source = """
      struct V: View {
        var body: some View {
          Button(action: {}) { Image(systemName: "gear") }.ojdAccessibilityLabel("Settings")
          Slider(value: $value, in: 0...1)
            .accessibilityLabel(Text("Level"))
          Picker(selection: $mode) { Text("A") }.labelsHidden()
            .ojdAccessibilityLabel(title)
          Image(systemName: "gear").accessibilityHidden(true)
          Image(decorative: "gear")
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }

  @Test
  func commentsAndInterpolatedStringsDoNotHideOrInventControls() {
    let source = """
      // Button(action: {}) { Image(systemName: "gear") }
      let text = "\\(Button("x") { Image(systemName: "gear") })"
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }

  @Test
  func aCastOrTypeTestIsNotAControl() {
    let source = """
      if let search = item as? NSSearchToolbarItem {}
      if let search = item as! NSSearchToolbarItem {}
      let isSearch = item is NSSearchToolbarItem
      let cast = item as NSToolbarItem
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }

  @Test
  func aLabelInsideAClosureDoesNotNameTheControl() {
    let source = """
      struct V: View {
        var body: some View {
          Slider(value: $value, in: 0...1).overlay { Text("x").accessibilityLabel("y") }
          Button { } label: { Image(systemName: "gear") }.overlay { Text("x") }
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").map(\.line) == [3, 4])
  }

  @Test
  func anEmptyLabelDoesNotNameTheControl() {
    let source = """
      struct V: View {
        var body: some View {
          Slider(value: $value, in: 0...1).accessibilityLabel("")
          Slider(value: $value, in: 0...1).ojdAccessibilityLabel(Text(verbatim: ""))
          Button { } label: { Text(verbatim: "") }
          Button { } label: { Text("") }
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").map(\.line) == [3, 4, 5, 6])
  }

  @Test
  func anImageInAPickerOptionNeedsItsOwnName() {
    let source = """
      struct V: View {
        var body: some View {
          Picker("Mode", selection: $mode) { Image(systemName: "gear").tag(1) }
          Picker("Mode", selection: $mode) {
            Image(systemName: "gear").accessibilityLabel("Gear").tag(1)
          }
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").map(\.line) == [3])
  }

  @Test
  func anAppKitControlNeedsItsOwnLabelCall() {
    let source = """
      func make() {
        let first = NSPopUpButton(frame: .zero, pullsDown: false)
        let second = NSPopUpButton(frame: .zero, pullsDown: false)
        second.setAccessibilityLabel("Second")
        let item = NSToolbarItem(itemIdentifier: id)
        let other = NSToolbarItem(itemIdentifier: id)
        other.label = "Other"
        let tied = NSPopUpButton(frame: .zero, pullsDown: false)
        tied.setAccessibilityTitleUIElement(title)
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").map(\.line) == [2, 5])
  }

  @Test
  func aSliderInTheLabelingRowIsNamedByTheRow() {
    let source = """
      struct V: View {
        var body: some View {
          InputTestSliderRow(title: "A", valueText: "1", accessibilityLabel: "A") {
            Slider(value: $value, in: 0...1)
          }
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }
}
