import Foundation

/// A control or image that VoiceOver cannot name.
struct UnlabeledControl: Equatable, CustomStringConvertible {
  let path: String
  let line: Int
  let kind: String

  var description: String { "\(path):\(line) \(kind)" }
}

/// Text scan of Swift sources for controls without an accessible name.
///
/// A SwiftUI control is named when its first argument is a title, when its label closure holds
/// a `Text` or `Label`, or when an accessibility label modifier is present; a `TextField` only by
/// the modifier. An image is named
/// when it carries an accessibility label or is hidden from accessibility, or when it sits
/// inside another control. An AppKit control is named when its function sets an accessibility
/// label, a toolbar item label, or an accessibility description.
enum AccessibilityAudit {
  /// SwiftUI controls whose name comes from a title argument or a label closure.
  static let titledControls: Set<String> = [
    "Button", "Toggle", "Picker", "Slider", "Stepper", "TextField", "SecureField", "Menu",
    "ColorPicker", "DatePicker", "Link", "NavigationLink", "TextEditor",
  ]

  /// Controls whose trailing closure is the label.
  ///
  /// A `Picker` or `Menu` trailing closure is the content, so only a `label:` closure names them.
  static let trailingLabelControls: Set<String> = [
    "Button", "Toggle", "Slider", "Stepper", "Link", "NavigationLink", "ColorPicker",
    "DatePicker",
  ]

  /// Controls whose title macOS shows as the placeholder, not as the accessible name, so they need
  /// an accessibility label beside it.
  static let placeholderTitledControls: Set<String> = ["TextField"]

  static let imageKinds: Set<String> = ["Image", "OJDSystemSymbol"]

  /// AppKit controls created in code.
  static let appKitControls: Set<String> = [
    "NSButton", "NSSlider", "NSStepper", "NSPopUpButton", "NSSwitch", "NSSegmentedControl",
    "NSComboBox", "NSSearchField", "NSToolbarItem", "NSSearchToolbarItem", "NSImageView",
  ]

  /// Toolbar item classes whose `label` is the accessible name.
  static let toolbarItems: Set<String> = ["NSToolbarItem", "NSSearchToolbarItem"]

  /// A view whose initializer requires an accessibility label for the control in its closure,
  /// so a control inside it needs no modifier of its own.
  static let labelingWrapper = "InputTestSliderRow"

  /// Controls whose unlabeled trailing closure is content, not a label.
  static let contentClosureControls: Set<String> = ["Picker", "Menu"]

  private struct Closure {
    let label: String?
    let text: String
    let range: Range<Int>
  }

  private struct Modifier {
    let name: String
    let arguments: String
  }

  private struct Extent {
    let name: String
    let start: Int
    let end: Int
    let arguments: String?
    let argumentsRange: Range<Int>?
    let closures: [Closure]
    let modifiers: [Modifier]
  }

  static func audit(source: String, path: String) -> [UnlabeledControl] {
    let bytes = stripComments(Array(source.utf8))
    var extents: [Extent] = []
    var index = 0
    while index < bytes.count {
      if bytes[index] == UInt8(ascii: "\"") {
        index = skipString(bytes, at: index)
        continue
      }
      guard isIdentifierStart(bytes[index]), index == 0 || !isIdentifierPart(bytes[index - 1]),
        index == 0 || bytes[index - 1] != UInt8(ascii: ".")
      else {
        index += 1
        continue
      }
      var end = index
      while end < bytes.count, isIdentifierPart(bytes[end]) { end += 1 }
      let name = text(bytes[index..<end])
      let tracked =
        titledControls.contains(name) || imageKinds.contains(name) || appKitControls.contains(name)
        || name == "Label" || name == labelingWrapper
      if tracked, opensExpression(bytes, at: end), !isDeclaration(bytes, before: index),
        !followsCast(bytes, before: index)
      {
        extents.append(extent(name: name, bytes: bytes, start: index, afterName: end))
      }
      index = end
    }
    return extents.compactMap { item in
      guard let kind = unnamedKind(item, within: extents, bytes: bytes) else { return nil }
      let line = bytes[0..<item.start].reduce(1) { $0 + ($1 == 10 ? 1 : 0) }
      return UnlabeledControl(path: path, line: line, kind: kind)
    }
  }

  // MARK: Classification

  private static func unnamedKind(_ item: Extent, within all: [Extent], bytes: [UInt8]) -> String? {
    let name = item.name
    if name == "Label" || name == labelingWrapper { return nil }
    if !imageKinds.contains(name), !appKitControls.contains(name),
      all.contains(where: {
        $0.name == labelingWrapper && $0.closures.contains { $0.range.contains(item.start) }
      })
    {
      return nil
    }
    if appKitControls.contains(name) { return appKitUnnamed(item, bytes: bytes) }
    if hasAccessibilityName(item.modifiers) { return nil }
    if name == "OJDSystemSymbol" {
      // The symbol view names itself from its fallback text and hides itself for a `nil`
      // fallback. A literal fallback is a glyph stand-in such as "->" that VoiceOver would read.
      let literal = item.arguments?.contains("fallback: \"") ?? false
      return literal ? "OJDSystemSymbol with a literal fallback and no accessibility label" : nil
    }
    if imageKinds.contains(name) {
      if item.arguments?.hasPrefix("decorative") == true { return nil }
      let enclosed = all.contains { isInsideLabel(item, of: $0) }
      return enclosed ? nil : "\(name) without an accessibility label or hidden trait"
    }
    if placeholderTitledControls.contains(name) {
      return "\(name) without an accessibility label"
    }
    if let first = item.arguments, titleArgument(first) { return nil }
    if let label = item.closures.first(where: { $0.label == "label" }) {
      return namesControl(label.text) ? nil : "\(name) with an unnamed label closure"
    }
    if trailingLabelControls.contains(name),
      let trailing = item.closures.last(where: { $0.label == nil })
    {
      let hasAction = item.arguments?.contains("action:") ?? false
      if hasAction || name != "Button", namesControl(trailing.text) { return nil }
    }
    return "\(name) without a title or accessibility label"
  }

  /// An image inside another control's arguments or label closures is part of that control.
  ///
  /// The content closure of a `Picker` or `Menu` and modifier closures are not.
  private static func isInsideLabel(_ image: Extent, of other: Extent) -> Bool {
    guard other.start < image.start, image.end <= other.end else { return false }
    if let range = other.argumentsRange, range.contains(image.start) { return true }
    return other.closures.contains { closure in
      guard closure.range.contains(image.start) else { return false }
      return closure.label != nil || !contentClosureControls.contains(other.name)
    }
  }

  private static func appKitUnnamed(_ item: Extent, bytes: [UInt8]) -> String? {
    if item.name == "NSButton",
      let first = item.arguments?.trimmingCharacters(in: .whitespacesAndNewlines),
      first.hasPrefix("title:") || first.hasPrefix("checkboxWithTitle:")
        || first.hasPrefix("radioButtonWithTitle:")
    {
      return nil
    }
    guard let variable = assignedVariable(bytes, before: item.start) else {
      return "\(item.name) without a variable to carry an accessibility label"
    }
    let scope = enclosingFunction(bytes, at: item.start)
    let scoped = text(bytes[scope])
    var markers = [
      "\(variable).setAccessibilityLabel(", "\(variable).setAccessibilityTitleUIElement(",
      "\(variable).accessibilityLabel =",
    ]
    if toolbarItems.contains(item.name) { markers.append("\(variable).label =") }
    if item.name == "NSSearchToolbarItem" {
      markers.append("\(variable).searchField.setAccessibilityLabel(")
    }
    let named = markers.contains { scoped.contains($0) }
    return named ? nil : "\(item.name) \(variable) without an accessibility label"
  }

  /// The name of the `let` or `var` whose initializer starts the expression at `index`.
  private static func assignedVariable(_ bytes: [UInt8], before index: Int) -> String? {
    let window = text(bytes[max(0, index - 300)..<index])
    guard let match = window.matches(of: /\b(?:let|var)\s+(\w+)/).last,
      window[match.range.upperBound...].contains("=")
    else { return nil }
    return String(match.1)
  }

  private static func hasAccessibilityName(_ modifiers: [Modifier]) -> Bool {
    modifiers.contains { modifier in
      let compact = modifier.arguments.filter { !$0.isWhitespace }
      if modifier.name.hasSuffix("ccessibilityLabel") {
        return !["", "\"\"", "Text(\"\")", "Text(verbatim:\"\")"].contains(compact)
      }
      if modifier.name == "accessibilityHidden" { return compact == "true" }
      return modifier.name == "ojdSymbolAccessibility"
    }
  }

  /// A first argument without an argument label is the title; `""` is no title.
  private static func titleArgument(_ arguments: String) -> Bool {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.hasPrefix("\"\"") { return false }
    if let colon = trimmed.firstIndex(of: ":"),
      trimmed[trimmed.startIndex..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
    {
      return false
    }
    return true
  }

  /// A label closure names a control when it holds a `Text` or `Label` with content.
  private static func namesControl(_ closure: String) -> Bool {
    var compact = closure.filter { !$0.isWhitespace }
    for empty in ["Text(\"\")", "Text(verbatim:\"\")"] {
      compact = compact.replacingOccurrences(of: empty, with: "")
    }
    return compact.contains("Text(") || compact.contains("Label(") || compact.contains("Text{")
  }

  // MARK: Extent parsing

  private static func extent(name: String, bytes: [UInt8], start: Int, afterName: Int) -> Extent {
    var position = afterName
    var arguments: String?
    var argumentsRange: Range<Int>?
    var closures: [Closure] = []
    var modifiers: [Modifier] = []
    var inModifiers = false
    var lastWasClosure = false
    var first = true
    while position < bytes.count {
      var next = position
      while next < bytes.count, isSpace(bytes[next]) { next += 1 }
      guard next < bytes.count else { break }
      let character = bytes[next]
      if character == UInt8(ascii: "("), next == position {
        let close = matchClose(bytes, open: next)
        if first {
          arguments = text(bytes[(next + 1)..<close])
          argumentsRange = (next + 1)..<close
        }
        position = close + 1
        first = false
        lastWasClosure = false
        continue
      }
      first = false
      if character == UInt8(ascii: "{") {
        let close = matchClose(bytes, open: next)
        if !inModifiers {
          closures.append(
            Closure(
              label: nil,
              text: text(bytes[(next + 1)..<close]),
              range: (next + 1)..<close
            )
          )
        }
        position = close + 1
        lastWasClosure = true
        continue
      }
      if character == UInt8(ascii: "."), next + 1 < bytes.count, isIdentifierStart(bytes[next + 1])
      {
        var end = next + 1
        while end < bytes.count, isIdentifierPart(bytes[end]) { end += 1 }
        let modifierName = text(bytes[(next + 1)..<end])
        var modifierArguments = ""
        position = end
        if end < bytes.count, bytes[end] == UInt8(ascii: "(") {
          let close = matchClose(bytes, open: end)
          modifierArguments = text(bytes[(end + 1)..<close])
          position = close + 1
        }
        modifiers.append(Modifier(name: modifierName, arguments: modifierArguments))
        inModifiers = true
        lastWasClosure = false
        continue
      }
      if lastWasClosure, !inModifiers, isIdentifierStart(character),
        let labeled = labeledClosure(bytes, at: next)
      {
        closures.append(labeled.closure)
        position = labeled.end
        continue
      }
      break
    }
    return Extent(
      name: name,
      start: start,
      end: position,
      arguments: arguments,
      argumentsRange: argumentsRange,
      closures: closures,
      modifiers: modifiers
    )
  }

  /// A closure introduced by `label: {` after a trailing closure.
  private static func labeledClosure(
    _ bytes: [UInt8],
    at index: Int
  ) -> (closure: Closure, end: Int)? {
    var end = index
    while end < bytes.count, isIdentifierPart(bytes[end]) { end += 1 }
    guard end < bytes.count, bytes[end] == UInt8(ascii: ":") else { return nil }
    var brace = end + 1
    while brace < bytes.count, isSpace(bytes[brace]) { brace += 1 }
    guard brace < bytes.count, bytes[brace] == UInt8(ascii: "{") else { return nil }
    let close = matchClose(bytes, open: brace)
    let label = text(bytes[index..<end])
    let text = text(bytes[(brace + 1)..<close])
    return (Closure(label: label, text: text, range: (brace + 1)..<close), close + 1)
  }

  /// A call `(` or a trailing closure `{` on the same line follows the name.
  private static func opensExpression(_ bytes: [UInt8], at index: Int) -> Bool {
    var next = index
    while next < bytes.count, bytes[next] == 32 { next += 1 }
    guard next < bytes.count else { return false }
    return bytes[index] == UInt8(ascii: "(") || bytes[next] == UInt8(ascii: "{")
  }

  /// A name after `as`, `as?`, `as!`, `is` or `->` is a type, not a call.
  private static func followsCast(_ bytes: [UInt8], before index: Int) -> Bool {
    var end = index
    while end > 0, bytes[end - 1] == 32 { end -= 1 }
    if end > 1, bytes[end - 1] == UInt8(ascii: ">"), bytes[end - 2] == UInt8(ascii: "-") {
      return true
    }
    if end > 0, bytes[end - 1] == UInt8(ascii: "?") || bytes[end - 1] == UInt8(ascii: "!") {
      end -= 1
    }
    var start = end
    while start > 0, isIdentifierPart(bytes[start - 1]) { start -= 1 }
    return ["as", "is"].contains(text(bytes[start..<end]))
  }

  /// `func`, `struct`, `class`, `enum` and `case` lines declare a name rather than call it.
  private static func isDeclaration(_ bytes: [UInt8], before index: Int) -> Bool {
    var start = index
    while start > 0, bytes[start - 1] != 10 { start -= 1 }
    let prefix = text(bytes[start..<index])
      .trimmingCharacters(in: .whitespaces)
    return ["func", "struct", "class", "enum", "case", "extension"].contains {
      prefix.hasSuffix($0)
    }
  }

  /// The byte range of the innermost function body that contains `index`, else the whole file.
  private static func enclosingFunction(_ bytes: [UInt8], at index: Int) -> Range<Int> {
    var open = index
    while open > 0 {
      open -= 1
      guard bytes[open] == UInt8(ascii: "{"), matchClose(bytes, open: open) >= index else {
        continue
      }
      var lineStart = open
      while lineStart > 0, bytes[lineStart - 1] != 10 { lineStart -= 1 }
      let header = text(bytes[lineStart..<open])
      if header.contains("func ") || header.contains("init(") {
        return open..<matchClose(bytes, open: open)
      }
    }
    return 0..<bytes.count
  }

  // MARK: Lexing

  private static func text(_ bytes: ArraySlice<UInt8>) -> String {
    // swiftlint:disable:next optional_data_string_conversion
    String(decoding: bytes, as: UTF8.self)
  }

  private static func isSpace(_ byte: UInt8) -> Bool {
    byte == 32 || byte == 10 || byte == 9 || byte == 13
  }

  private static func isIdentifierStart(_ byte: UInt8) -> Bool {
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
  }

  private static func isIdentifierPart(_ byte: UInt8) -> Bool {
    isIdentifierStart(byte) || (byte >= 48 && byte <= 57)
  }

  /// Replaces comments with spaces and keeps newlines so line numbers stay valid.
  static func stripComments(_ bytes: [UInt8]) -> [UInt8] {
    var output = bytes
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      if byte == UInt8(ascii: "\"") {
        index = skipString(bytes, at: index)
      } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count,
        bytes[index + 1] == UInt8(ascii: "/")
      {
        while index < bytes.count, bytes[index] != 10 {
          output[index] = 32
          index += 1
        }
      } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count,
        bytes[index + 1] == UInt8(ascii: "*")
      {
        while index + 1 < bytes.count,
          !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/"))
        {
          if bytes[index] != 10 { output[index] = 32 }
          index += 1
        }
        if index < bytes.count { output[index] = 32 }
        if index + 1 < bytes.count { output[index + 1] = 32 }
        index += 2
      } else {
        index += 1
      }
    }
    return output
  }

  /// Returns the index after the string literal that opens at `index`, with interpolations.
  static func skipString(_ bytes: [UInt8], at index: Int) -> Int {
    let multiline =
      index + 2 < bytes.count && bytes[index + 1] == UInt8(ascii: "\"")
      && bytes[index + 2] == UInt8(ascii: "\"")
    var position = index + (multiline ? 3 : 1)
    while position < bytes.count {
      let byte = bytes[position]
      if byte == UInt8(ascii: "\\") {
        if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "(") {
          position = matchClose(bytes, open: position + 1) + 1
        } else {
          position += 2
        }
        continue
      }
      if byte == UInt8(ascii: "\"") {
        if !multiline { return position + 1 }
        if position + 2 < bytes.count, bytes[position + 1] == UInt8(ascii: "\""),
          bytes[position + 2] == UInt8(ascii: "\"")
        {
          return position + 3
        }
      }
      if byte == 10, !multiline { return position }
      position += 1
    }
    return bytes.count
  }

  /// Returns the index of the bracket that closes the one at `open`.
  static func matchClose(_ bytes: [UInt8], open: Int) -> Int {
    let opener = bytes[open]
    let closer: UInt8 = opener == UInt8(ascii: "(") ? UInt8(ascii: ")") : UInt8(ascii: "}")
    var depth = 0
    var position = open
    while position < bytes.count {
      let byte = bytes[position]
      if byte == UInt8(ascii: "\"") {
        position = skipString(bytes, at: position)
        continue
      }
      if byte == opener { depth += 1 }
      if byte == closer {
        depth -= 1
        if depth == 0 { return position }
      }
      position += 1
    }
    return bytes.count - 1
  }
}
