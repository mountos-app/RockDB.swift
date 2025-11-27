//
//  RocksDBLiteTests.swift
//  RocksDB.swift
//
//  Tests for RocksDB Lite Swift wrapper
//

import XCTest
@testable import RocksDBSwiftLite

final class RocksDBLiteTests: XCTestCase {

  var tempDirectory: URL!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RocksDBLiteTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    super.tearDown()
  }

  // MARK: - Basic Operations

  func testOpenAndClose() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDBLite.open(at: dbPath)
    XCTAssertTrue(db.isOpen)
    db.close()
    XCTAssertFalse(db.isOpen)
  }

  func testOpenReadOnly() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path

    // First create and populate the database
    let db = try RocksDBLite.open(at: dbPath)
    try db.put("value", forKey: "key")
    db.close()

    // Open read-only
    let readOnlyDb = try RocksDBLite.openReadOnly(at: dbPath)
    XCTAssertTrue(readOnlyDb.isOpen)
    XCTAssertEqual(try readOnlyDb.getString("key"), "value")
    readOnlyDb.close()
  }

  func testPutAndGet() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDBLite.open(at: dbPath)
    defer { db.close() }

    let key = "test-key".data(using: .utf8)!
    let value = "test-value".data(using: .utf8)!

    try db.put(value, forKey: key)
    let retrieved = try db.get(key)

    XCTAssertEqual(retrieved, value)
  }

  func testStringConvenience() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDBLite.open(at: dbPath)
    defer { db.close() }

    try db.put("hello", forKey: "greeting")
    let result = try db.getString("greeting")

    XCTAssertEqual(result, "hello")
  }

  func testGetNonExistent() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDBLite.open(at: dbPath)
    defer { db.close() }

    let result = try db.get("nonexistent".data(using: .utf8)!)
    XCTAssertNil(result)
  }

  func testDelete() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDBLite.open(at: dbPath)
    defer { db.close() }

    let key = "to-delete"
    try db.put("some-value", forKey: key)
    XCTAssertNotNil(try db.getString(key))

    try db.delete(key)
    XCTAssertNil(try db.getString(key))
  }

  func testMultipleOperations() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDBLite.open(at: dbPath)
    defer { db.close() }

    // Write multiple keys
    for i in 0..<100 {
      try db.put("value-\(i)", forKey: "key-\(i)")
    }

    // Read them back
    for i in 0..<100 {
      let value = try db.getString("key-\(i)")
      XCTAssertEqual(value, "value-\(i)")
    }

    // Delete some
    for i in 0..<50 {
      try db.delete("key-\(i)")
    }

    // Verify deleted
    for i in 0..<50 {
      XCTAssertNil(try db.getString("key-\(i)"))
    }

    // Verify remaining
    for i in 50..<100 {
      XCTAssertEqual(try db.getString("key-\(i)"), "value-\(i)")
    }
  }

  func testDatabaseClosed() throws {
    let dbPath = tempDirectory.appendingPathComponent("test.db").path
    let db = try RocksDBLite.open(at: dbPath)
    db.close()

    XCTAssertThrowsError(try db.put("value", forKey: "key")) { error in
      guard case RocksDBLiteError.databaseClosed = error else {
        XCTFail("Expected databaseClosed error")
        return
      }
    }
  }

  // MARK: - Performance

  func testWritePerformance() throws {
    let dbPath = tempDirectory.appendingPathComponent("perf.db").path
    let db = try RocksDBLite.open(at: dbPath)
    defer { db.close() }

    measure {
      do {
        for i in 0..<1000 {
          try db.put("value-\(i)", forKey: "key-\(i)")
        }
      } catch {
        XCTFail("Write failed: \(error)")
      }
    }
  }

  func testReadPerformance() throws {
    let dbPath = tempDirectory.appendingPathComponent("perf.db").path
    let db = try RocksDBLite.open(at: dbPath)
    defer { db.close() }

    // Populate
    for i in 0..<1000 {
      try db.put("value-\(i)", forKey: "key-\(i)")
    }

    measure {
      do {
        for i in 0..<1000 {
          _ = try db.getString("key-\(i)")
        }
      } catch {
        XCTFail("Read failed: \(error)")
      }
    }
  }
}
