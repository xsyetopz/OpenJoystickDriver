// swift-tools-version: 6.4
// Runs swift-bedrock for `just`: swift run --package-path BuildTools swift-bedrock
import PackageDescription

let package = Package(
  name: "BuildTools",
  platforms: [.macOS(.v12)],
  dependencies: [
    .package(url: "https://github.com/xsyetopz/bedrock", revision: "swift-bedrock-v0.1.3")
  ]
)
