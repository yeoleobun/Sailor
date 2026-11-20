// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sailor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sailor", targets: ["Sailor"])
    ],
    targets: [
        .executableTarget(
            name: "Sailor",
            path: "Sources/Sailor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("Network"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
