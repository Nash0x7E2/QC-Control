// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BoseBar", platforms: [.macOS(.v13)], products: [.library(name: "BoseProtocol", targets: ["BoseProtocol"])], targets: [
 .target(name: "BoseProtocol"),
 .testTarget(name: "BoseProtocolTests", dependencies: ["BoseProtocol"])
])
