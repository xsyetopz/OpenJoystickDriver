import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SoakCheckLocalizationTests {
  private let mebibyte: UInt64 = 1_048_576

  /// Numbers as the catalog prints them: through the current locale.
  private func decimal(_ value: Double) -> String {
    unsafe String(format: "%.1f", locale: .current, value)
  }

  /// A count inside a plural entry: formatted with the locale of the selected language.
  private func pluralInteger(_ value: Int) -> String {
    unsafe String(format: "%d", locale: Locale(identifier: "en_US"), value)
  }

  private func integer(_ value: Int) -> String {
    unsafe String(format: "%d", locale: .current, value)
  }

  private func stableSummary() throws -> RuntimeHealthSummary {
    let samples = (0..<7).map { index in
      RuntimeHealthSample(
        elapsedNanoseconds: UInt64(index) * 10_000_000_000,
        residentBytes: 50 * mebibyte,
        physicalFootprintBytes: 40 * mebibyte,
        cumulativeCPUNanoseconds: UInt64(index) * 1_000_000,
        fileDescriptorCount: 12,
        threadCount: 4
      )
    }
    return try #require(ApplicationServiceRuntimeHealthAnalyzer.summarize(samples))
  }

  @Test
  func theDetailIsWordedByTheCatalogAndNeverStartsWithTheMachineIdentifier() throws {
    let summary = try stableSummary()
    #expect(summary.soakVerdict == .stable)

    let check = DiagnosticsService.soakCheck(summary)

    #expect(check.status == .pass)
    #expect(
      check.detail
        == "Stable: resident size \(decimal(50)) MiB, footprint \(decimal(40)) MiB, "
        + "file descriptors 12, CPU \(decimal(0))% over 60 s"
    )
  }

  @Test
  func everyVerdictAndErrorHasAResolvedEntryInEveryLocale() {
    let verdictKeys = RuntimeSoakVerdict.allCases.map(DiagnosticsService.verdictKey)
    let errorKeys = [
      "cli.diagnose.group.soakErrorProcessUnavailable",
      "cli.diagnose.group.soakErrorInvalidConfiguration",
      "cli.diagnose.group.soakErrorTooManySamples",
      "cli.diagnose.group.soakErrorNoSamples",
    ]
    #expect(Set(verdictKeys).count == RuntimeSoakVerdict.allCases.count)

    for locale in Localization().availableLocalizations {
      let localization = Localization(preferredLanguages: [locale])
      for key in verdictKeys {
        let detail = localization.formatted(key, arguments: [50.0, 40.0, 12, 1.5, 60.0])
        #expect(detail != key, "\(locale) \(key)")
        #expect(!detail.contains("$"), "\(locale) \(key)")
      }
      for key in errorKeys {
        #expect(localization.string(key) != key, "\(locale) \(key)")
      }
    }
  }

  @Test
  func samplingErrorsAreDescribedByTheCatalog() {
    #expect(
      RuntimeHealthSamplingError.processUnavailable(4_242).errorDescription
        == "Could not read runtime information for service process \(integer(4_242))."
    )
    #expect(
      RuntimeHealthSamplingError.invalidConfiguration.errorDescription
        == "Runtime sampling needs 1...\(integer(86_400)) seconds and a sample interval of "
        + "100...\(integer(60_000)) ms."
    )
    #expect(
      RuntimeHealthSamplingError.tooManySamples(900_000).errorDescription
        == "Runtime sampling would take \(pluralInteger(900_000)) samples. "
        + "Raise the sample interval."
    )
    #expect(
      RuntimeHealthSamplingError.noSamples.errorDescription
        == "The service produced no runtime samples."
    )
  }
}
