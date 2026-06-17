import AppKit
import OpenJoystickDriverKit
import SwiftUI

struct OJDCard<Content: View>: View {
  private let title: String?
  private let content: Content

  init(title: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let title {
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
      }
      content
    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(
      RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
        Color(NSColor.controlBackgroundColor)
      )
    ).overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
        Color.secondary.opacity(0.16),
        lineWidth: 1
      )
    )
  }
}

struct StatusOrb: View {
  let isReady: Bool
  let isBusy: Bool

  var body: some View {
    ZStack {
      Circle().fill(
        (isReady ? Color.green : (isBusy ? Color.orange : Color.secondary)).opacity(0.14)
      )
      Circle().fill(isReady ? Color.green : (isBusy ? Color.orange : Color.secondary)).frame(
        width: 10,
        height: 10
      )
    }.frame(width: 28, height: 28)
  }
}

struct MetricChip: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
      Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
    }.padding(.horizontal, 9).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.08))
      )
  }
}

struct PermissionRow: View {
  let title: String
  let subtitle: String
  let state: String
  let actionTitle: String
  var disabled = false
  let action: () -> Void

  private var isGranted: Bool { state == "granted" }
  private var isDenied: Bool { state == "denied" }
  private var symbolName: String {
    if isGranted { return "checkmark" }
    if isDenied { return "exclamationmark" }
    return "ellipsis"
  }
  private var statusLabel: String {
    switch state {
    case "granted": return L10n.string("access.allowed")
    case "denied": return L10n.string("access.needsApproval")
    default: return L10n.string("access.notSetUp")
    }
  }
  private var statusColor: Color {
    if isGranted { return .green }
    if isDenied { return .orange }
    return .secondary
  }

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      permissionIndicator

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(title).font(.caption.weight(.semibold))
          Text(statusLabel).font(.system(size: 10, weight: .semibold)).foregroundColor(statusColor)
        }
        Text(subtitle).font(.caption).foregroundColor(.secondary).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
      Spacer()
      SwiftUI.Button(actionTitle, action: action).controlSize(.small).disabled(
        disabled || isGranted
      )
    }
  }

  @ViewBuilder private var permissionIndicator: some View {
    if #available(macOS 11.0, *) {
      Image(systemName: symbolName).font(.system(size: 10, weight: .bold)).foregroundColor(
        statusColor
      ).frame(width: 22, height: 22).background(Circle().fill(statusColor.opacity(0.12)))
    } else {
      Text(isGranted ? "✓" : (isDenied ? "!" : "…")).font(.caption.weight(.bold)).foregroundColor(
        statusColor
      ).frame(width: 22, height: 22).background(Circle().fill(statusColor.opacity(0.12)))
    }
  }
}

struct PermissionAssistView: View {
  let message: String

  var body: some View {
    Text(message).font(.caption).foregroundColor(.secondary).fixedSize(
      horizontal: false,
      vertical: true
    ).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(
      RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.08))
    )
  }
}

struct MiniBadge: View {
  let title: String

  init(_ title: String) { self.title = title }

  var body: some View {
    Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).lineLimit(1)
      .padding(.horizontal, 7).padding(.vertical, 4).background(
        Capsule().fill(Color.secondary.opacity(0.10))
      )
  }
}

@MainActor final class InputTestWindowController {
  private let compactSize = NSSize(width: 860, height: 560)
  private var window: NSWindow?

  func show(model: AppModel) {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let root = InputTestWindowView().environmentObject(model)
    let hosting = NSHostingController(rootView: root)
    let newWindow = NSWindow(contentViewController: hosting)
    newWindow.title = L10n.string("input.title")
    newWindow.setContentSize(compactSize)
    newWindow.minSize = compactSize
    newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    newWindow.isReleasedWhenClosed = false
    newWindow.center()
    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = newWindow
  }
}
