import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Runs `OJDRepositoryTool mask-image` on a PNG drawn here: an opaque image whose every pixel has
/// its own color, standing for a `screencapture -R` image of the frame at `scale` pixels a point.
struct MaskImageTests {
  /// The frame in global points, top-left origin, and the two menu windows inside it: a parent
  /// menu on the left and a shorter submenu on its right, so the corners of the frame beside the
  /// submenu belong to neither.
  private static let frame = "100,33,30,20"
  private static let parent = "100,33,10,20"
  private static let submenu = "110,38,20,10"

  private struct Pixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
  }

  private static func color(x: Int, y: Int) -> Pixel {
    Pixel(red: UInt8(x * 2), green: UInt8(y * 3), blue: 200, alpha: 255)
  }

  private static func writeImage(width: Int, height: Int, to url: URL) throws {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let pixel = color(x: x, y: y)
        let offset = (y * width + x) * 4
        bytes[offset] = pixel.red
        bytes[offset + 1] = pixel.green
        bytes[offset + 2] = pixel.blue
        bytes[offset + 3] = pixel.alpha
      }
    }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let image = try unsafe #require(
      CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    )
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
  }

  /// The pixels of the PNG at `url`, rows from the top, as sRGB with premultiplied alpha.
  private static func readImage(_ url: URL) throws -> (width: Int, pixels: [Pixel]) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try unsafe #require(
        CGContext(
          data: buffer.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      )
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let pixels = stride(from: 0, to: bytes.count, by: 4).map {
      Pixel(red: bytes[$0], green: bytes[$0 + 1], blue: bytes[$0 + 2], alpha: bytes[$0 + 3])
    }
    return (width, pixels)
  }

  @Test(arguments: [2, 3])
  func onlyPixelsOfMenuWindowsStay(scale: Int) throws {
    try OJDRepositoryToolTests.scratch { directory in
      let image = directory.appendingPathComponent("menu.png")
      let width = 30 * scale
      let height = 20 * scale
      try Self.writeImage(width: width, height: height, to: image)
      let result = try OJDRepositoryToolTests.run([
        "mask-image", image.path, Self.frame, Self.parent, Self.submenu,
      ])
      #expect(result.status == 0, "\(result.standardError)")
      #expect(result.standardOutput.isEmpty)
      let masked = try Self.readImage(image)
      #expect(masked.width == width)
      #expect(masked.pixels.count == width * height)
      for y in 0..<height {
        for x in 0..<width {
          let inParent = x < 10 * scale
          let inSubmenu = x >= 10 * scale && y >= 5 * scale && y < 15 * scale
          let expected =
            inParent || inSubmenu
            ? Self.color(x: x, y: y) : Pixel(red: 0, green: 0, blue: 0, alpha: 0)
          let found = masked.pixels[y * width + x]
          guard found == expected else {
            Issue.record("pixel \(x),\(y) at \(scale)x is \(found), expected \(expected)")
            return
          }
        }
      }
    }
  }

  @Test
  func menuWindowOutsideFrameIsRefusedAndImageStays() throws {
    try OJDRepositoryToolTests.scratch { directory in
      let image = directory.appendingPathComponent("menu.png")
      try Self.writeImage(width: 60, height: 40, to: image)
      let before = try Data(contentsOf: image)
      let result = try OJDRepositoryToolTests.run([
        "mask-image", image.path, Self.frame, "120,33,20,20",
      ])
      #expect(result.status == 64)
      #expect(result.standardError.contains("120,33,20,20 is not inside the frame 100,33,30,20"))
      #expect(try Data(contentsOf: image) == before)
    }
  }

  @Test
  func callThatToolRefusesExitsWith64() throws {
    try OJDRepositoryToolTests.scratch { directory in
      let image = directory.appendingPathComponent("menu.png")
      try Self.writeImage(width: 60, height: 40, to: image)
      let missing = directory.appendingPathComponent("missing.png").path
      for arguments in [
        ["mask-image", image.path, Self.frame],
        ["mask-image", image.path, "100,33,30", Self.parent],
        ["mask-image", image.path, "100,33,0,20", Self.parent],
        ["mask-image", image.path, Self.frame, "100,33,10,nan"],
        ["mask-image", missing, Self.frame, Self.parent],
      ] {
        let result = try OJDRepositoryToolTests.run(arguments)
        #expect(result.status == 64, "\(arguments)")
        #expect(result.standardOutput.isEmpty, "\(arguments)")
      }
    }
  }
}
