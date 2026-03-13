// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let buildForWasm = ProcessInfo.processInfo.environment["NEAT_WASM"] == "1"

var neatTargets: [String] = ["Neat"]
if !buildForWasm {
    neatTargets.append("NeatVapor")
}

var products: [Product] = [
    .library(name: "Neat", targets: neatTargets)
]

if !buildForWasm {
    products.append(.library(name: "NeatVapor", targets: ["NeatVapor"]))
}

var dependencies: [Package.Dependency] = []

if !buildForWasm {
    dependencies.append(.package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"))
}

var targets: [Target] = [
    .target(
        name: "Neat",
        dependencies: [],
        path: "Sources/Neat",
        resources: [.process("Resources")]
    )
]

if !buildForWasm {
    targets.append(
        .target(
            name: "NeatVapor",
            dependencies: [
                "Neat",
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/LEGACY_NeatVapor"
        )
    )
}
let package = Package(
    name: "Neat",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
