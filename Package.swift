// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Cliptara",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Cliptara", targets: ["Cliptara"])
    ],
    targets: [
        .executableTarget(
            name: "Cliptara",
            path: "Sources/Cliptara"
        )
    ]
)
