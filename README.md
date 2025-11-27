# RocksDB.swift

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![RocksDB 9.7.4](https://img.shields.io/badge/RocksDB-9.7.4-blue.svg)](https://rocksdb.org)
[![License](https://img.shields.io/badge/License-Apache%202.0%20%2F%20GPLv2-green.svg)](LICENSE)

A Swift wrapper for [RocksDB](https://rocksdb.org/) using Swift 6 C++ interoperability. Built with claude AI.

## Features

- Thread-safe database operations
- Key-value operations (put, get, delete)
- Batch writes for atomic operations
- Optimistic transactions with savepoints
- Iterators with Sequence conformance
- Configurable compression (Snappy, LZ4, Zstd, etc.)
- Optimized presets for point lookups and bulk loading

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## Building RocksDB

Before using the package, you need to build the RocksDB static library:

```bash
# Install build tools
brew install cmake ninja

# Full build (with compression support, self-contained)
./Scripts/build_rocksdb.sh

# OR slim build (no compression)
./Scripts/build_rocksdb.sh --slim
```

| Build | Compression       | Size  | Dependencies      |
| ----- | ----------------- | ----- | ----------------- |
| Full  | Snappy, LZ4, Zstd | ~46MB | None (all static) |
| Slim  | None              | ~44MB | None              |

**Slim build**: After building, remove from `Package.swift`:

```swift
.linkedLibrary("snappy"),
.linkedLibrary("lz4"),
.linkedLibrary("zstd"),
```

This creates universal (arm64 + x86_64) static libraries in the `lib/` directory.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/mountos-app/RockDB.swift.git", from: "1.0.0")
]
```

Then add one of the products to your target dependencies:

| Product            | Description                                             |
| ------------------ | ------------------------------------------------------- |
| `RocksDBSwift`     | Full-featured (transactions, iterators, batch, options) |
| `RocksDBSwiftLite` | Lightweight (basic key-value: get, put, delete)         |

```swift
.target(
  name: "YourTarget",
  dependencies: [
    .product(name: "RocksDBSwift", package: "RocksDBSwift"),
    // OR for lightweight version:
    // .product(name: "RocksDBSwiftLite", package: "RocksDBSwift"),
  ]
)
```

## Usage

### Lite API (RocksDBSwiftLite)

For simple key-value storage with minimal API surface:

```swift
import RocksDBSwiftLite

let db = try RocksDBLite.open(at: "/path/to/db")
defer { db.close() }

// Basic operations
try db.put("hello", forKey: "greeting")
let value = try db.getString("greeting")  // "hello"
try db.delete("greeting")

// Binary data
try db.put(imageData, forKey: "avatar".data(using: .utf8)!)
let data = try db.get("avatar".data(using: .utf8)!)
```

### Full API (RocksDBSwift)

For advanced features like transactions, iterators, and batch operations:

```swift
import RocksDBSwift

// Open database
let db = try RocksDB.open(at: "/path/to/db")
defer { db.close() }

// Put and get
try db.put("hello", forKey: "greeting")
let value = try db.getString("greeting") // "hello"

// Delete
try db.delete("greeting")
```

### Batch Operations

```swift
try db.batch { batch in
  batch.put("value1", forKey: "key1")
  batch.put("value2", forKey: "key2")
  batch.delete("old-key")
}
```

### Transactions

```swift
let db = try RocksDB.openWithTransactions(at: "/path/to/db")

let result = try db.transaction { txn in
  let current = try txn.getForUpdate("counter".data(using: .utf8)!)
  let newValue = (current.flatMap { Int(String(data: $0, encoding: .utf8)!) } ?? 0) + 1
  try txn.put("\(newValue)", forKey: "counter")
  return newValue
}
```

### Iterators

```swift
let iter = try db.makeIterator()
defer { iter.close() }

// Use as Sequence
for (key, value) in iter {
  print("Key: \(String(data: key, encoding: .utf8)!)")
}

// Or manually
iter.seekToFirst()
while iter.isValid {
  print(iter.keyString ?? "")
  iter.next()
}
```

### Prefix Iteration

```swift
let prefix = "user:".data(using: .utf8)!
try db.forEachWithPrefix(prefix) { key, value in
  print("Found user key: \(String(data: key, encoding: .utf8)!)")
  return true // continue iteration
}
```

### Custom Options

```swift
var options = RocksDBOptions()
options.compression = .zstd
options.writeBufferSize = 128 * 1024 * 1024
options.maxOpenFiles = 500

let db = try RocksDB.open(at: path, options: options)
```

### Optimized Presets

```swift
// For point lookups (random reads)
let db = try RocksDB.open(at: path, options: .pointLookup(blockCacheSizeMB: 64))

// For bulk loading
let db = try RocksDB.open(at: path, options: .bulkLoad)
```

## License

This project is dual-licensed under both the Apache 2.0 and GPLv2 licenses,
the same as RocksDB itself. See [LICENSE](LICENSE) for details.
