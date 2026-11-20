import Testing

@testable import OpenJoystickDriverKit

/// A provider that counts its listings and reports a change count the test sets.
private actor ListingCountingProvider: USBTransportProvider {
  private let listed: [USBTransportDevice]
  private(set) var listings = 0
  private var changes: UInt64?

  init(devices: [USBTransportDevice], changeCount: UInt64?) {
    listed = devices
    changes = changeCount
  }

  var enumerationChangeCount: UInt64? { changes }

  func devices() -> [USBTransportDevice] {
    listings += 1
    return listed
  }

  func change() { changes = changes.map { $0 + 1 } }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) throws -> any USBTransportSession { throw USBTransportError.notSupported }
}

struct USBEnumerationListingTests {
  private let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 0x41,
    vendorID: 0x045E,
    productID: 0x02EA,
    locationID: 0x0110_0000
  )

  /// A tracker that acknowledges every device of `devices`.
  private func settled(_ devices: [USBTransportDevice]) -> USBEnumerationTracker {
    var tracker = USBEnumerationTracker()
    for device in devices { tracker.acknowledge(device) }
    return tracker
  }

  /// Polls `provider` `count` times at `now`, keeping the listing between polls.
  private func poll(
    _ provider: ListingCountingProvider,
    tracker: USBEnumerationTracker,
    times count: Int,
    last: inout USBEnumerationListing?,
    now: UInt64 = 0
  ) async {
    for _ in 0..<count {
      _ = await pollUSBEnumeration(from: provider, tracker: tracker, last: &last, now: now)
    }
  }

  @Test
  func unchangedSettledEnumerationIsListedOnce() async {
    let provider = ListingCountingProvider(devices: [device], changeCount: 0)
    var last: USBEnumerationListing?

    await poll(provider, tracker: settled([device]), times: 10, last: &last)

    #expect(await provider.listings == 1)
  }

  @Test
  func reportedChangeListsAgain() async {
    let provider = ListingCountingProvider(devices: [device], changeCount: 0)
    var last: USBEnumerationListing?
    await poll(provider, tracker: settled([device]), times: 1, last: &last)

    await provider.change()
    await poll(provider, tracker: settled([device]), times: 1, last: &last)

    #expect(await provider.listings == 2)
  }

  @Test
  func unacknowledgedDeviceListsEveryPoll() async {
    let provider = ListingCountingProvider(devices: [device], changeCount: 0)
    var last: USBEnumerationListing?

    await poll(provider, tracker: USBEnumerationTracker(), times: 3, last: &last)

    #expect(await provider.listings == 3)
  }

  @Test
  func listingOlderThanMaxAgeListsAgain() async {
    let provider = ListingCountingProvider(devices: [device], changeCount: 0)
    var last: USBEnumerationListing?
    let tracker = settled([device])
    await poll(provider, tracker: tracker, times: 1, last: &last, now: 0)

    await poll(provider, tracker: tracker, times: 1, last: &last, now: 4_999_999_999)
    await poll(provider, tracker: tracker, times: 1, last: &last, now: 5_000_000_000)

    #expect(await provider.listings == 2)
  }

  @Test
  func providerWithoutChangeCountListsEveryPoll() async {
    let provider = ListingCountingProvider(devices: [device], changeCount: nil)
    var last: USBEnumerationListing?

    await poll(provider, tracker: settled([device]), times: 3, last: &last)

    #expect(await provider.listings == 3)
  }
}
