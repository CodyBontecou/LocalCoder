// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clibgit2",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Clibgit2", targets: ["Clibgit2", "libgit2"]),
    ],
    targets: [
        .target(
            name: "Clibgit2",
            dependencies: ["libgit2"],
            publicHeadersPath: "include"
        ),
        .binaryTarget(
            name: "libgit2",
            path: "../../libgit2.xcframework"
        ),
    ]
)
