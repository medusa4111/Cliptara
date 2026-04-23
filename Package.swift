// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "iShot",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "iShot", targets: ["iShot"])
    ],
    targets: [
        .executableTarget(
            name: "iShot",
            path: "Sources/iShot"
        )
    ]
)
