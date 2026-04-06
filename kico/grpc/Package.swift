// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "grpc",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "grpc",
            targets: ["grpc"]
        ),
    ],
    dependencies: [
        // 添加官方 Protobuf 依赖
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.36.1"),
        // 添加 Connect-Swift 依赖
        .package(url: "https://github.com/connectrpc/connect-swift.git", from: "1.2.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "grpc",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Connect", package: "connect-swift"),
            ]
        ),
        .testTarget(
            name: "grpcTests",
            dependencies: ["grpc"]
        ),
    ]
)
