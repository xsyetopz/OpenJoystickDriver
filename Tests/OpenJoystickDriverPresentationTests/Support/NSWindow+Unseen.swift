import AppKit

@MainActor
extension NSWindow {
  /// Keeps the window and each sheet AppKit attaches to it out of sight while it is on screen.
  ///
  /// A sheet orders its parent in and takes the parent's level. The minimum window level stacks
  /// both behind the desktop picture, so a test can check what AppKit only does on screen, such as
  /// `isVisible` or `attachedSheet`, without a window appearing in front of the person at the Mac.
  func keepUnseen() {
    level = Level(rawValue: Int(CGWindowLevelForKey(.minimumWindow)))
    alphaValue = 0
    ignoresMouseEvents = true
  }

  /// Orders the window in behind the desktop picture without activating the app.
  func orderInUnseen() {
    keepUnseen()
    orderFront(nil)
  }
}
