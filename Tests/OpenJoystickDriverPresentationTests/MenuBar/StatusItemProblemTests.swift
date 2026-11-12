import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// The problem rows and the icon of `specs/menu-bar-item/spec.md`.
@Suite
struct StatusItemProblemTests {
  // A service that does not answer asks the platform host for the login item.
  init() { PlatformHosts.install(FakePlatformHost()) }

  private static func pad() -> StatusItemState.Controller {
    StatusItemState.Controller(id: "a", name: "Pad", isSuspended: false, isWireless: false)
  }

  private static func state(
    problems: [StatusItemProblem] = [],
    controllers: [StatusItemState.Controller] = [pad()]
  ) -> StatusItemState {
    StatusItemState(problems: problems, controllers: controllers, profileListRead: true)
  }

  private static func rows(_ state: StatusItemState) -> [StatusItemEntry] {
    StatusItemModel.entries(for: state).filter { !$0.isSeparator }
  }

  private static func titles(_ entries: [StatusItemEntry]) -> [StatusItemTitle] {
    entries.flatMap { [$0.title] + titles($0.submenu ?? []) }
  }

  @Test
  func missingPermissionRowIsFirstNamesThePermissionAndOpensItsPlaceInAccess() throws {
    let menu = Self.rows(Self.state(problems: [.missingPermission(.inputRead)]))
    let first = try #require(menu.first)
    #expect(first.id == "problem.inputRead")
    #expect(
      first.title == .formatted("ui.extra.problemPermission", .key("platform.macos.term.inputRead"))
    )
    #expect(first.action == .showPermission(.inputRead))
    #expect(menu.dropFirst().first?.id == "controller.a")
  }

  @Test
  func eachMissingPermissionGetsItsOwnRowBeforeTheControllers() {
    let menu = Self.rows(
      Self.state(problems: [.missingPermission(.inputRead), .missingPermission(.inputInject)])
    )
    #expect(
      menu.map(\.id) == [
        "problem.inputRead", "problem.inputInject", "controller.a", "openWindow", "settings",
        "quit",
      ]
    )
  }

  @Test
  func unreachableServiceRowOffersToStartIt() throws {
    let menu = Self.rows(Self.state(problems: [.service(.stopped)], controllers: []))
    let first = try #require(menu.first)
    #expect(first.id == "problem.service")
    #expect(first.title == .key("ui.banner.service.title"))
    #expect(first.action == .startService)
    #expect(first.isEnabled)
  }

  @Test
  func noProblemMeansNoProblemRowAndNoNeedsAttentionText() {
    let menu = Self.rows(Self.state())
    #expect(!menu.contains { $0.id.hasPrefix("problem.") })
    #expect(!Self.titles(menu).contains(.key("status.needsAttention")))
    let withProblem = Self.rows(Self.state(problems: [.service(.stopped)]))
    #expect(!Self.titles(withProblem).contains(.key("status.needsAttention")))
  }

  @Test
  func problemRowsAreTheOnlyAdditionsToTheMenu() {
    let plain = Self.rows(Self.state()).map(\.id)
    let withProblem = Self.rows(Self.state(problems: [.service(.stopped)])).map(\.id)
    #expect(withProblem == ["problem.service"] + plain)
  }

  // MARK: the caller, MenuBarViewModel

  @MainActor
  private static func viewModel(gateway: GatewayStub) async -> MenuBarViewModel {
    let runtime = RuntimeViewModel(gateway: gateway)
    await runtime.refresh()
    return MenuBarViewModel(runtime: runtime)
  }

  @Test
  @MainActor
  func deniedInputMonitoringReachesTheMenuAsAProblemThatNamesIt() async {
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .denied,
        inputInject: .granted,
        connectedDevices: [],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )
    let model = await Self.viewModel(gateway: gateway)
    #expect(model.statusItemState.problems == [.missingPermission(.inputRead)])
  }

  @Test
  @MainActor
  func anUnreachableServiceReachesTheMenuAsTheServiceProblem() async {
    let model = await Self.viewModel(
      gateway: GatewayStub(statusShouldFail: true, statusError: .notConnected)
    )
    #expect(model.statusItemState.problems.first == .service(.notInstalled))
  }

  @Test
  @MainActor
  func aReadyServiceWithNoControllerHasNoProblem() async {
    let model = await Self.viewModel(gateway: GatewayStub())
    #expect(model.statusItemState.problems.isEmpty)
    #expect(model.statusItemState.controllers.isEmpty)
  }

  // MARK: the icon

  @Test
  func theIconChangesShapeWhileAProblemRowExists() {
    let ready = StatusItemModel.symbolName(for: Self.state())
    for problem in [StatusItemProblem.service(.stopped), .missingPermission(.inputRead)] {
      #expect(StatusItemModel.symbolName(for: Self.state(problems: [problem])) != ready)
    }
  }

  @Test
  func noControllerConnectedKeepsTheReadyIcon() {
    #expect(
      StatusItemModel.symbolName(for: Self.state(controllers: []))
        == StatusItemModel.symbolName(for: Self.state())
    )
  }

  @Test
  func theAccessibilityLabelNamesTheState() {
    #expect(StatusItemModel.accessibilityTitle(for: Self.state()) == .key("a11y.menuBar.ready"))
    #expect(
      StatusItemModel.accessibilityTitle(for: Self.state(controllers: []))
        == .key("a11y.menuBar.noController")
    )
    #expect(
      StatusItemModel.accessibilityTitle(
        for: Self.state(problems: [.missingPermission(.inputInject), .service(.stopped)])
      )
        == .formatted(
          "a11y.menuBar.problem",
          .formatted("ui.extra.problemPermission", .key("platform.macos.term.inputInject"))
        )
    )
  }
}
