// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ComicOptimizer",
    platforms: [.macOS(.v13)],
    targets: [
        // macOS ships libarchive 3.7.4 (zip/rar/rar5/7z read, zip write) but no headers.
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("archive")]),
        .executableTarget(name: "ComicOptimizer", dependencies: ["CArchive"]),
    ]
)
