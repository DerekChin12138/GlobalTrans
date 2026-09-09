// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlobalTrans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "GlobalTrans", targets: ["GlobalTrans"]),
        .executable(name: "gt-ocr-cli", targets: ["GTOCRCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "GlobalTransCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/GlobalTransCore"
        ),
        .executableTarget(
            name: "GTOCRCLI",
            dependencies: ["GlobalTransCore"],
            path: "Sources/GTOCRCLI"
        ),
        .executableTarget(
            name: "GlobalTrans",
            dependencies: ["GlobalTransCore"],
            path: "Sources/GlobalTrans",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
