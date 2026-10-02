// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImageMarkupKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "ImageMarkupKit", targets: ["ImageMarkupKit"]),
    ],
    targets: [
        .target(name: "ImageMarkupKit"),
        .testTarget(
            name: "ImageMarkupKitTests",
            dependencies: ["ImageMarkupKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
