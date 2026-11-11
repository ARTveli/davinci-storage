// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DaVinciStorage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StorageCore", targets: ["StorageCore"]),
    ],
    targets: [
        .target(name: "StorageCore"),
        .executableTarget(name: "davinci-storage", dependencies: ["StorageCore"]),
        .executableTarget(name: "DaVinciStorageApp", dependencies: ["StorageCore"]),
        // Command Line Tools only (no Xcode): point the compiler at the swift-testing macro plugin
        // and the linker/runtime at Testing.framework.
        .testTarget(
            name: "StorageCoreTests",
            dependencies: ["StorageCore"],
            swiftSettings: [.unsafeFlags([
                "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
            ])],
            linkerSettings: [.unsafeFlags([
                "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
            ])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
