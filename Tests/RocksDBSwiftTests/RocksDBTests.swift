//
//  RocksDBTests.swift
//  RocksDB.swift
//
//  Tests for RocksDB Swift wrapper
//

import XCTest
@testable import RocksDBSwift

final class RocksDBTests: XCTestCase {

  var tempDirectory: URL!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RocksDBTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    super.tearDown()
  }

  // MARK: - Basic Operations

  func testOpenAndClose() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    XCTAssertTrue(db.isOpen)
    db.close()
    XCTAssertFalse(db.isOpen)
  }

  func testPutAndGet() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    let key = "test-key".data(using: .utf8)!
    let value = "test-value".data(using: .utf8)!

    try db.put(value, forKey: key)
    let retrieved = try db.get(key)

    XCTAssertEqual(retrieved, value)
  }

  func testStringConvenience() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    try db.put("hello", forKey: "greeting")
    let result = try db.getString("greeting")

    XCTAssertEqual(result, "hello")
  }

  func testGetNonExistent() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    let result = try db.get("nonexistent".data(using: .utf8)!)
    XCTAssertNil(result)
  }

  func testDelete() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    let key = "to-delete".data(using: .utf8)!
    let value = "some-value".data(using: .utf8)!

    try db.put(value, forKey: key)
    XCTAssertNotNil(try db.get(key))

    try db.delete(key)
    XCTAssertNil(try db.get(key))
  }

  func testKeyMayExist() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    let key = "exists".data(using: .utf8)!
    try db.put("value".data(using: .utf8)!, forKey: key)

    // Note: keyMayExist can have false positives but should return true for existing keys
    XCTAssertTrue(db.keyMayExist(key))
  }

  // MARK: - Batch Operations

  func testBatch() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    try db.batch { batch in
      batch.put("value1", forKey: "key1")
      batch.put("value2", forKey: "key2")
      batch.put("value3", forKey: "key3")
    }

    XCTAssertEqual(try db.getString("key1"), "value1")
    XCTAssertEqual(try db.getString("key2"), "value2")
    XCTAssertEqual(try db.getString("key3"), "value3")
  }

  func testBatchWithDelete() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    // First add some data
    try db.put("initial", forKey: "delete-me")

    // Batch with both put and delete
    try db.batch { batch in
      batch.put("new-value", forKey: "new-key")
      batch.delete("delete-me")
    }

    XCTAssertEqual(try db.getString("new-key"), "new-value")
    XCTAssertNil(try db.getString("delete-me"))
  }

  // MARK: - Iterator Tests

  func testIterator() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    // Insert sorted data
    try db.put("a-value", forKey: "a")
    try db.put("b-value", forKey: "b")
    try db.put("c-value", forKey: "c")

    let iter = try db.makeIterator()
    defer { iter.close() }

    var keys: [String] = []
    iter.seekToFirst()
    while iter.isValid {
      if let key = iter.keyString {
        keys.append(key)
      }
      iter.next()
    }
    try iter.checkStatus()

    XCTAssertEqual(keys, ["a", "b", "c"])
  }

  func testIteratorSequence() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    try db.put("1", forKey: "key1")
    try db.put("2", forKey: "key2")
    try db.put("3", forKey: "key3")

    let iter = try db.makeIterator()
    defer { iter.close() }

    var count = 0
    for _ in iter {
      count += 1
    }

    XCTAssertEqual(count, 3)
  }

  func testForEach() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    try db.put("1", forKey: "a")
    try db.put("2", forKey: "b")
    try db.put("3", forKey: "c")

    var count = 0
    try db.forEach { _, _ in
      count += 1
      return true
    }

    XCTAssertEqual(count, 3)
  }

  func testForEachWithPrefix() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    try db.put("val1", forKey: "prefix:1")
    try db.put("val2", forKey: "prefix:2")
    try db.put("val3", forKey: "other:1")

    var prefixedKeys: [String] = []
    let prefix = "prefix:".data(using: .utf8)!

    try db.forEachWithPrefix(prefix) { key, _ in
      if let keyStr = String(data: key, encoding: .utf8) {
        prefixedKeys.append(keyStr)
      }
      return true
    }

    XCTAssertEqual(prefixedKeys.count, 2)
    XCTAssertTrue(prefixedKeys.allSatisfy { $0.hasPrefix("prefix:") })
  }

  // MARK: - Transaction Tests

  func testTransaction() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.openWithTransactions(at: dbPath)
    defer { db.close() }

    XCTAssertTrue(db.isTransactional)

    let result = try db.transaction { txn in
      try txn.put("txn-value", forKey: "txn-key")
      return try txn.getString("txn-key")
    }

    XCTAssertEqual(result, "txn-value")

    // Verify committed
    XCTAssertEqual(try db.getString("txn-key"), "txn-value")
  }

  func testTransactionRollback() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.openWithTransactions(at: dbPath)
    defer { db.close() }

    // Put initial value
    try db.put("initial", forKey: "rollback-test")

    // Transaction that fails
    do {
      _ = try db.transaction { txn in
        try txn.put("new-value", forKey: "rollback-test")
        throw RocksDBError.invalidArgument("Intentional failure")
      }
      XCTFail("Should have thrown")
    } catch {
      // Expected
    }

    // Value should be unchanged
    XCTAssertEqual(try db.getString("rollback-test"), "initial")
  }

  func testTransactionSavepoint() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.openWithTransactions(at: dbPath)
    defer { db.close() }

    let txn = try db.beginTransaction()

    try txn.put("value1", forKey: "key1")
    txn.setSavepoint()

    try txn.put("value2", forKey: "key2")

    // Rollback to savepoint
    try txn.rollbackToSavepoint()

    // key2 should be gone, key1 should remain
    try txn.commit()

    XCTAssertEqual(try db.getString("key1"), "value1")
    XCTAssertNil(try db.getString("key2"))
  }

  // MARK: - Options Tests

  func testCustomOptions() throws {
    var options = RocksDBOptions()
    options.compression = .zstd
    options.writeBufferSize = 128 * 1024 * 1024
    options.maxOpenFiles = 500

    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath, options: options)
    defer { db.close() }

    try db.put("test", forKey: "key")
    XCTAssertEqual(try db.getString("key"), "test")
  }

  func testPointLookupOptions() throws {
    let options = RocksDBOptions.pointLookup(blockCacheSizeMB: 64)

    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath, options: options)
    defer { db.close() }

    try db.put("test", forKey: "key")
    XCTAssertEqual(try db.getString("key"), "test")
  }

  // MARK: - Maintenance Tests

  func testFlush() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    try db.put("test", forKey: "key")
    try db.flush()
  }

  func testCompactRange() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    // Add some data
    for i in 0..<100 {
      try db.put("value-\(i)", forKey: "key-\(i)")
    }

    try db.compactRange()
  }

  func testGetProperty() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    // Add some data
    for i in 0..<10 {
      try db.put("value-\(i)", forKey: "key-\(i)")
    }

    // These properties should exist
    XCTAssertNotNil(db.estimatedKeyCount)
    XCTAssertNotNil(db.getProperty("rocksdb.stats"))
  }

  // MARK: - Performance Tests

  func testBulkWritePerformance() throws {
    let dbPath = tempDirectory.appendingPathComponent("perf.db").path
    let options = RocksDBOptions.bulkLoad
    let db = try RocksDB.open(at: dbPath, options: options)
    defer { db.close() }

    let count = 10000

    measure {
      do {
        try db.batch { batch in
          for i in 0..<count {
            batch.put("value-\(i)", forKey: "key-\(i)")
          }
        }
      } catch {
        XCTFail("Batch write failed: \(error)")
      }
    }
  }

  func testRandomReadPerformance() throws {
    let dbPath = tempDirectory.appendingPathComponent("perf.db").path
    let db = try RocksDB.open(at: dbPath)
    defer { db.close() }

    let count = 1000

    // Populate
    try db.batch { batch in
      for i in 0..<count {
        batch.put("value-\(i)", forKey: "key-\(i)")
      }
    }

    measure {
      do {
        for i in 0..<count {
          _ = try db.getString("key-\(i)")
        }
      } catch {
        XCTFail("Read failed: \(error)")
      }
    }
  }
}
