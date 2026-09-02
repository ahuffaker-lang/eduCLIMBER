// swift-tools-version:5.9
import PackageDescription

// Open this file in Xcode ("File > Open..." and select Package.swift), pick the
// eduCLIMBER-Converter scheme, and press Run. `scripts/build_app.sh` wraps the
// release build into a double-clickable eduCLIMBER Converter.app.
let package = Package(
    name: "eduCLIMBERConverter",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "eduCLIMBER-Converter", targets: ["EduClimberConverterApp"]),
        .library(name: "EduClimberKit", targets: ["EduClimberKit"]),
    ],
    targets: [
        // All the conversion logic: file reading, column matching, validation,
        // field mapping, CSV output. No UI, so it is fully unit-testable.
        .target(name: "EduClimberKit", path: "Sources/EduClimberKit"),
        // The AppKit app shell.
        .executableTarget(
            name: "EduClimberConverterApp",
            dependencies: ["EduClimberKit"],
            path: "Sources/EduClimberConverterApp"
        ),
        .testTarget(
            name: "EduClimberKitTests",
            dependencies: ["EduClimberKit"],
            path: "Tests/EduClimberKitTests"
        ),
    ]
)
