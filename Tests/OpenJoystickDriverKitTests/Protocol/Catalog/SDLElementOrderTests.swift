import Testing

@testable import OpenJoystickDriverKit

struct SDLElementOrderTests {
  @Test
  func axesSortByUsageNumber() {
    let lists = SDLElementLists(
      elements: [
        sdlElement(1, 0x35, order: 0), sdlElement(1, 0x30, order: 1), sdlElement(1, 0x31, order: 2),
        sdlElement(2, 0xC4, order: 3), sdlElement(2, 0xBB, order: 4),
      ]
    )
    #expect(lists.axes.map(\.usage) == [0x30, 0x31, 0x35, 0xBB, 0xC4])
    #expect(lists.hats.isEmpty && lists.buttons.isEmpty)
  }

  @Test
  func hatsAreHatSwitchUsage() {
    let lists = SDLElementLists(
      elements: [sdlElement(1, 0x39, order: 0, range: 0...7), sdlElement(1, 0x39, order: 1)]
    )
    #expect(lists.hats.map(\.arrivalOrder) == [0, 1])
    #expect(lists.axes.isEmpty)
  }

  @Test
  func buttonsSortByUsageNumberAcrossPages() {
    let lists = SDLElementLists(
      elements: [
        sdlElement(9, 100, order: 0), sdlElement(0x0C, 0x40, order: 1), sdlElement(9, 1, order: 2),
        sdlElement(1, 0x90, order: 3),
      ]
    )
    #expect(lists.buttons.map(\.usage) == [1, 0x40, 100, 0x90])
    #expect(lists.buttons.map(\.usagePage) == [9, 0x0C, 9, 1])
  }

  @Test
  func equalUsagesKeepArrivalOrder() {
    let lists = SDLElementLists(
      elements: [
        sdlElement(0x0C, 1, order: 5), sdlElement(9, 1, order: 2), sdlElement(9, 1, order: 9),
      ]
    )
    #expect(lists.buttons.map(\.arrivalOrder) == [2, 5, 9])
  }

  @Test
  func arrivalOrderComesFromFieldNotArrayPosition() {
    let lists = SDLElementLists(
      elements: [sdlElement(9, 1, cookie: 1, order: 1), sdlElement(9, 1, cookie: 2, order: 0)]
    )
    #expect(lists.buttons.map(\.cookie) == [2, 1])
  }

  @Test
  func duplicateCookiesAreDroppedPerList() {
    let lists = SDLElementLists(
      elements: [
        sdlElement(9, 1, cookie: 7, order: 0), sdlElement(9, 2, cookie: 7, order: 1),
        sdlElement(1, 0x30, cookie: 7, order: 2),
      ]
    )
    #expect(lists.buttons.map(\.usage) == [1])
    #expect(lists.axes.map(\.usage) == [0x30])
  }

  @Test
  func otherUsagesJoinNoList() {
    let lists = SDLElementLists(
      elements: [
        sdlElement(0xFF00, 1, order: 0), sdlElement(1, 0x01, order: 1), sdlElement(8, 1, order: 2),
      ]
    )
    #expect(lists.axes.isEmpty && lists.hats.isEmpty && lists.buttons.isEmpty)
  }
}
