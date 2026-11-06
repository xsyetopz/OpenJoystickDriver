import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A rectangle in global points with a top-left origin, written `x,y,width,height` as
/// `screencapture -R` takes it.
struct ScreenRectangle {
  /// The text that the rectangle is parsed from, kept for error messages.
  let text: String
  /// The left edge in points.
  let minX: Double
  /// The top edge in points.
  let minY: Double
  /// The width in points; greater than zero.
  let width: Double
  /// The height in points; greater than zero.
  let height: Double
  /// The right edge in points.
  var maxX: Double { minX + width }
  /// The bottom edge in points.
  var maxY: Double { minY + height }

  /// Parses `text` as four comma-separated finite numbers with a positive width and height.
  ///
  /// - Throws: ``UsageError`` when `text` is not four finite numbers or the rectangle has no area.
  init(_ text: String) throws {
    let values = text.split(separator: ",", omittingEmptySubsequences: false).map {
      Double(String($0))
    }
    guard values.count == 4, let x = values[0], let y = values[1], let width = values[2],
      let height = values[3], [x, y, width, height].allSatisfy(\.isFinite)
    else { throw UsageError(message: "\(text) is not x,y,width,height") }
    guard width > 0, height > 0 else {
      throw UsageError(message: "\(text) has no area")
    }
    self.text = text
    minX = x
    minY = y
    self.width = width
    self.height = height
  }

  /// Whether `other` lies entirely inside this rectangle, edges included.
  func contains(_ other: Self) -> Bool {
    other.minX >= minX && other.minY >= minY && other.maxX <= maxX && other.maxY <= maxY
  }
}

/// The `mask-image` subcommand of `OJDRepositoryTool`.
///
/// Makes every pixel of a `screencapture -R <frame>` PNG that lies outside all `keep` rectangles
/// fully transparent and leaves the pixels inside them unchanged. The pixels per point come from
/// the image size over the frame size on each axis, since the image is at the display's backing
/// scale. A keep rectangle covers every pixel it touches, so its edges stay whole.
enum MaskImage {
  /// Masks the PNG at `arguments[0]` in place, keeping the rectangles in `arguments[2...]`.
  ///
  /// - Parameter arguments: The image path, the frame rectangle, then one or more rectangles to
  ///   keep.
  /// - Throws: ``UsageError`` when the arguments are too few, a keep rectangle is outside the
  ///   frame, or the file is not an RGB PNG that can be masked, encoded and written.
  static func run(_ arguments: [String]) throws {
    guard arguments.count >= 3, let path = arguments.first else {
      throw UsageError(message: "mask-image takes an image, a frame and a rectangle to keep")
    }
    let frame = try ScreenRectangle(arguments[1])
    let keep = try arguments.dropFirst(2).map(ScreenRectangle.init)
    for rectangle in keep where !frame.contains(rectangle) {
      throw UsageError(message: "\(rectangle.text) is not inside the frame \(frame.text)")
    }
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetType(source) as String? == UTType.png.identifier,
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw UsageError(message: "\(path) is not a PNG image") }
    guard let space = image.colorSpace, space.model == .rgb else {
      throw UsageError(message: "\(path) is not an RGB image")
    }
    let width = image.width
    let height = image.height
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { throw UsageError(message: "\(path) cannot be drawn into an RGBA image") }
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    context.clear(bounds)
    context.interpolationQuality = .none
    context.setShouldAntialias(false)
    context.clip(
      to: keep.map { pixels($0, frame: frame, width: width, height: height) }
    )
    context.draw(image, in: bounds)
    guard let masked = context.makeImage() else {
      throw UsageError(message: "\(path) cannot be masked")
    }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { throw UsageError(message: "a PNG cannot be encoded") }
    // The source properties keep the image's resolution, so it shows at its point size.
    CGImageDestinationAddImage(
      destination,
      masked,
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
    )
    guard CGImageDestinationFinalize(destination) else {
      throw UsageError(message: "the masked \(path) cannot be encoded as PNG")
    }
    do {
      try (data as Data).write(to: url, options: .atomic)
    } catch {
      throw UsageError(message: "\(path) cannot be written: \(error.localizedDescription)")
    }
  }

  /// The pixels of `rectangle` in an image of `frame`, in the bottom-left origin of a `CGContext`.
  private static func pixels(
    _ rectangle: ScreenRectangle,
    frame: ScreenRectangle,
    width: Int,
    height: Int
  ) -> CGRect {
    let scaleX = Double(width) / frame.width
    let scaleY = Double(height) / frame.height
    // The frame holds the rectangle, so only rounding can reach past the image edge.
    let left = max(0, ((rectangle.minX - frame.minX) * scaleX).rounded(.down))
    let right = min(Double(width), ((rectangle.maxX - frame.minX) * scaleX).rounded(.up))
    let top = max(0, ((rectangle.minY - frame.minY) * scaleY).rounded(.down))
    let bottom = min(Double(height), ((rectangle.maxY - frame.minY) * scaleY).rounded(.up))
    return CGRect(x: left, y: Double(height) - bottom, width: right - left, height: bottom - top)
  }
}
