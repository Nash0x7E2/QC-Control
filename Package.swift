// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BoseBar", platforms: [.macOS(.v13)], products: [.executable(name: "BoseBar", targets: ["BoseBar"])], targets: [
 .target(name: "BoseProtocol"),
 .executableTarget(name: "BoseBar", dependencies: ["BoseProtocol"], linkerSettings: [.linkedFramework("IOBluetooth")]),
 .testTarget(name: "BoseProtocolTests", dependencies: ["BoseProtocol"])
])
