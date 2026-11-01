// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NucleoPet",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PetDomain", targets: ["PetDomain"]),
        .executable(name: "PetPreview", targets: ["PetPreview"])
    ],
    targets: [
        .target(name: "CPetCore", publicHeadersPath: "include"),
        .target(name: "PetDomain", dependencies: ["CPetCore"]),
        .executableTarget(name: "PetPreview", dependencies: ["PetDomain"], path: "App", exclude: ["Assets.xcassets"]),
        .testTarget(name: "PetDomainTests", dependencies: ["PetDomain"])
    ]
)
