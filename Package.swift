// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SimpleVM",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "simple-vm", targets: ["SimpleVM"])
    ],
    targets: [
        .executableTarget(
            name: "SimpleVM",
            path: "Sources/SimpleVM",
            linkerSettings: [
                .linkedFramework("Virtualization"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
