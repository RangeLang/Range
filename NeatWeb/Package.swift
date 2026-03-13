// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let buildForWasm = ProcessInfo.processInfo.environment["NEAT_WASM"] == "1"

var neatTargets: [String] = ["NeatWeb"]
if !buildForWasm {
    neatTargets.append("NeatWebVapor")
}

var products: [Product] = [
    .library(name: "NeatWeb", targets: neatTargets)
]

if !buildForWasm {
    products.append(.library(name: "NeatWebVapor", targets: ["NeatWebVapor"]))
}

var dependencies: [Package.Dependency] = []

if !buildForWasm {
    dependencies.append(.package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"))
}

var targets: [Target] = [
    .target(
        name: "NeatWeb",
        dependencies: [],
        path: "Sources/Neat",
        resources: [.process("Resources")]
    )
]

if !buildForWasm {
    targets.append(
        .target(
            name: "NeatWebVapor",
            dependencies: [
                "NeatWeb",
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/LEGACY_NeatVapor"
        )
    )
}
let package = Package(
    name: "NeatWeb",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
