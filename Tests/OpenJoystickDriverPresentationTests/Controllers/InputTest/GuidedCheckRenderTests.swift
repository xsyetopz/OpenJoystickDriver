import AppKit
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import SwiftUI
import Testing

@testable import OpenJoystickDriverPresentation

/// Renders the guided check views into a window-less bitmap.
///
/// With `OJD_GUIDED_CHECK_EVIDENCE` set to a folder, each render is written there as a PNG;
/// without it the renders are only measured.
@Suite("Guided check render")
@MainActor
struct GuidedCheckRenderTests {
  private let device = ApplicationServiceDeviceDescription.fixture(
    id: "pad",
    serialNumber: "SN-7F3A-SECRET",
    capabilities: ControllerCapabilities(controls: [.south, .east])
  )

  private func environment() -> GuidedCheckEnvironment {
    GuidedCheckEnvironment(
      record: { _ in nil },
      saveDirectory: FileManager.default.temporaryDirectory,
      reveal: { _ in },
      open: { _ in },
      copy: { _ in }
    )
  }

  private func finishedModel(responding: Bool) -> GuidedCheckModel {
    let model = GuidedCheckModel(environment: environment())
    model.start(device)
    model.observe(.neutral)
    if responding {
      var state = ControllerState.neutral
      state.pressed = [.south]
      model.observe(state)
      model.observe(.neutral)
      state.pressed = [.east]
      model.observe(state)
    } else {
      model.skip()
      model.skip()
    }
    return model
  }

  private func render(_ view: some View, named name: String) throws {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: rep)
    #expect(rep.pixelsWide > 0)
    guard let folder = ProcessInfo.processInfo.environment["OJD_GUIDED_CHECK_EVIDENCE"] else {
      return
    }
    let png = try #require(rep.representation(using: .png, properties: [:]))
    let directory = URL(fileURLWithPath: folder, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: directory.appendingPathComponent("\(name).png"))
  }

  @Test
  func stepViewAndEndSheetsRender() throws {
    let running = GuidedCheckModel(environment: environment())
    running.start(device)
    running.observe(.neutral)
    try render(
      GuidedCheckRow(check: running, canStart: true) {}.padding().frame(width: 520),
      named: "step"
    )
    try render(
      GuidedCheckRow(check: GuidedCheckModel(environment: environment()), canStart: true) {}
        .padding().frame(width: 520),
      named: "button"
    )
    try render(GuidedCheckEndSheet(check: finishedModel(responding: true)), named: "end-sheet")
    try render(
      GuidedCheckEndSheet(check: finishedModel(responding: false)),
      named: "end-sheet-skipped"
    )
    try render(
      GuidedCheckValidationSheet(check: finishedModel(responding: true)),
      named: "validation-sheet"
    )
  }
}
