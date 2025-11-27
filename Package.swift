// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "RocksDBSwift",
  platforms: [.macOS(.v14)],
  products: [
    // Full-featured RocksDB wrapper (transactions, iterators, batch, etc.)
    .library(name: "RocksDBSwift", targets: ["RocksDBSwift"]),
    // Lightweight wrapper for basic key-value operations only
    .library(name: "RocksDBSwiftLite", targets: ["RocksDBSwiftLite"]),
  ],
  targets: [
    // C++ bridge module
    .target(
      name: "CRocksDB",
      path: "Sources/CRocksDB",
      sources: ["RocksDBBridge.cpp"],
      publicHeadersPath: "include",
      cxxSettings: [
        .headerSearchPath("../../lib/include"),
        .unsafeFlags(["-std=c++20"])
      ],
      linkerSettings: [
        .unsafeFlags(["-L\(Context.packageDirectory)/lib"]),
        .linkedLibrary("rocksdb"),
        .linkedLibrary("snappy"),
        .linkedLibrary("lz4"),
        .linkedLibrary("zstd"),
        .linkedLibrary("z"),
        .linkedLibrary("c++"),
      ]
    ),

    // Full Swift wrapper with C++ interop
    .target(
      name: "RocksDBSwift",
      dependencies: ["CRocksDB"],
      path: "Sources/RocksDBSwift",
      swiftSettings: [
        .interoperabilityMode(.Cxx),
      ]
    ),

    // Lightweight Swift wrapper for basic key-value operations
    .target(
      name: "RocksDBSwiftLite",
      dependencies: ["CRocksDB"],
      path: "Sources/RocksDBSwiftLite",
      swiftSettings: [
        .interoperabilityMode(.Cxx),
      ]
    ),

    // Tests for full wrapper
    .testTarget(
      name: "RocksDBSwiftTests",
      dependencies: ["RocksDBSwift"],
      path: "Tests/RocksDBSwiftTests",
      swiftSettings: [
        .interoperabilityMode(.Cxx),
      ]
    ),

    // Tests for lite wrapper
    .testTarget(
      name: "RocksDBSwiftLiteTests",
      dependencies: ["RocksDBSwiftLite"],
      path: "Tests/RocksDBSwiftLiteTests",
      swiftSettings: [
        .interoperabilityMode(.Cxx),
      ]
    ),
  ],
  cxxLanguageStandard: .cxx20
)
