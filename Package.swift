// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MySSH",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "MySSH", targets: ["MySSHAppKit"]),
        .executable(name: "MySSHAskPass", targets: ["MySSHAskPass"]),
        .library(name: "MySSHCore", targets: ["MySSHCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")
    ],
    targets: [
        .target(name: "MySSHCore"),
        .executableTarget(
            name: "MySSHAppKit",
            dependencies: ["MySSHCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .executableTarget(name: "MySSHAskPass", dependencies: ["MySSHCore"]),
        .testTarget(name: "MySSHCoreTests", dependencies: ["MySSHCore"])
    ]
)
