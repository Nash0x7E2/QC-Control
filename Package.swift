// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "QCControl", platforms: [.macOS(.v13)], products: [.library(name: "BoseProtocol", targets: ["BoseProtocol"]), .executable(name: "QCControl", targets: ["QCControl"])], targets: [
 .target(name: "BoseProtocol"),
 .executableTarget(name: "QCControl", dependencies: ["BoseProtocol"], linkerSettings: [.linkedFramework("IOBluetooth")]),
 .testTarget(name: "BoseProtocolTests", dependencies: ["BoseProtocol"]),
 .testTarget(name: "QCControlTests", dependencies: ["QCControl"])
])
