// swift-tools-version:5.9
import PackageDescription

let mtFrameworkFlags: [String] = [
    "-F", "/System/Library/PrivateFrameworks",
    "-framework", "MultitouchSupport",
]

let package = Package(
    name: "OnTouch",
    platforms: [.macOS(.v13)],
    targets: [
        // C shim that declares the private MultitouchSupport API and links the framework.
        .target(
            name: "CMultitouch",
            linkerSettings: [.unsafeFlags(mtFrameworkFlags)]
        ),
        .executableTarget(
            name: "OnTouch",
            dependencies: ["CMultitouch"],
            linkerSettings: [.unsafeFlags(mtFrameworkFlags)]
        ),
    ]
)
