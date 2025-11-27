//
//  RocksDBLite.swift
//  RocksDB.swift
//
//  Lightweight RocksDB wrapper for basic key-value operations
//

import Foundation
import CRocksDB

/// Lightweight thread-safe RocksDB wrapper for basic key-value operations
public final class RocksDBLite: @unchecked Sendable {
  private var handle: RocksDBRef?
  private let lock = NSRecursiveLock()

  /// Database path
  public let path: String

  /// Whether database is open
  public var isOpen: Bool {
    lock.withLock { handle != nil }
  }

  // MARK: - Initialization

  private init(handle: RocksDBRef, path: String) {
    self.handle = handle
    self.path = path
  }

  deinit {
    close()
  }

  // MARK: - Factory Methods

  /// Open a RocksDB database
  /// - Parameters:
  ///   - path: Path to database directory
  ///   - createIfMissing: Create database if it doesn't exist (default: true)
  /// - Returns: Open database instance
  /// - Throws: RocksDBLiteError on failure
  public static func open(at path: String, createIfMissing: Bool = true) throws -> RocksDBLite {
    let opts = rocksdb_options_create()
    defer { rocksdb_options_destroy(opts) }

    rocksdb_options_set_create_if_missing(opts, createIfMissing ? 1 : 0)

    var dbHandle: RocksDBRef?
    let status = rocksdb_open(path, opts, &dbHandle)

    if status.code != RocksDBStatusOK {
      let message = status.message.map { String(cString: $0) } ?? "Unknown error"
      if let msg = status.message {
        rocksdb_free_string(msg)
      }
      throw RocksDBLiteError.openFailed(message)
    }

    guard let handle = dbHandle else {
      throw RocksDBLiteError.openFailed("Failed to open database")
    }

    return RocksDBLite(handle: handle, path: path)
  }

  /// Open a RocksDB database in read-only mode
  /// - Parameter path: Path to database directory
  /// - Returns: Open database instance
  /// - Throws: RocksDBLiteError on failure
  public static func openReadOnly(at path: String) throws -> RocksDBLite {
    let opts = rocksdb_options_create()
    defer { rocksdb_options_destroy(opts) }

    var dbHandle: RocksDBRef?
    let status = rocksdb_open_for_read_only(path, opts, 0, &dbHandle)

    if status.code != RocksDBStatusOK {
      let message = status.message.map { String(cString: $0) } ?? "Unknown error"
      if let msg = status.message {
        rocksdb_free_string(msg)
      }
      throw RocksDBLiteError.openFailed(message)
    }

    guard let handle = dbHandle else {
      throw RocksDBLiteError.openFailed("Failed to open database")
    }

    return RocksDBLite(handle: handle, path: path)
  }

  /// Close the database
  public func close() {
    lock.withLock {
      if let h = handle {
        rocksdb_close(h)
        handle = nil
      }
    }
  }

  // MARK: - Basic Operations

  /// Put a key-value pair
  /// - Parameters:
  ///   - value: Value data
  ///   - key: Key data
  /// - Throws: RocksDBLiteError on failure
  public func put(_ value: Data, forKey key: Data) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBLiteError.databaseClosed
      }

      let writeOpts = rocksdb_write_options_create()
      defer { rocksdb_write_options_destroy(writeOpts) }

      let status = key.withUnsafeBytes { keyPtr in
        value.withUnsafeBytes { valuePtr in
          rocksdb_put(h, writeOpts,
                      keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                      key.count,
                      valuePtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                      value.count)
        }
      }

      if status.code != RocksDBStatusOK {
        let message = status.message.map { String(cString: $0) } ?? "Put failed"
        if let msg = status.message {
          rocksdb_free_string(msg)
        }
        throw RocksDBLiteError.operationFailed(message)
      }
    }
  }

  /// Get value for key
  /// - Parameter key: Key data
  /// - Returns: Value data or nil if not found
  /// - Throws: RocksDBLiteError on failure
  public func get(_ key: Data) throws -> Data? {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBLiteError.databaseClosed
      }

      let readOpts = rocksdb_read_options_create()
      defer { rocksdb_read_options_destroy(readOpts) }

      var valuePtr: UnsafeMutablePointer<CChar>?
      var valueLen: Int = 0

      let status = key.withUnsafeBytes { keyPtr in
        rocksdb_get(h, readOpts,
                    keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                    key.count,
                    &valuePtr,
                    &valueLen)
      }

      if status.code == RocksDBStatusNotFound {
        if let msg = status.message {
          rocksdb_free_string(msg)
        }
        return nil
      }

      if status.code != RocksDBStatusOK {
        let message = status.message.map { String(cString: $0) } ?? "Get failed"
        if let msg = status.message {
          rocksdb_free_string(msg)
        }
        throw RocksDBLiteError.operationFailed(message)
      }

      guard let ptr = valuePtr else {
        return nil
      }
      defer { rocksdb_free_data(ptr) }

      return Data(bytes: ptr, count: valueLen)
    }
  }

  /// Delete a key
  /// - Parameter key: Key data
  /// - Throws: RocksDBLiteError on failure
  public func delete(_ key: Data) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBLiteError.databaseClosed
      }

      let writeOpts = rocksdb_write_options_create()
      defer { rocksdb_write_options_destroy(writeOpts) }

      let status = key.withUnsafeBytes { keyPtr in
        rocksdb_delete(h, writeOpts,
                       keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                       key.count)
      }

      if status.code != RocksDBStatusOK {
        let message = status.message.map { String(cString: $0) } ?? "Delete failed"
        if let msg = status.message {
          rocksdb_free_string(msg)
        }
        throw RocksDBLiteError.operationFailed(message)
      }
    }
  }

  // MARK: - String Convenience Methods

  /// Put string value for string key
  public func put(_ value: String, forKey key: String) throws {
    guard let keyData = key.data(using: .utf8),
          let valueData = value.data(using: .utf8) else {
      throw RocksDBLiteError.invalidEncoding
    }
    try put(valueData, forKey: keyData)
  }

  /// Get string value for string key
  public func getString(_ key: String) throws -> String? {
    guard let keyData = key.data(using: .utf8) else {
      throw RocksDBLiteError.invalidEncoding
    }
    guard let data = try get(keyData) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Delete string key
  public func delete(_ key: String) throws {
    guard let keyData = key.data(using: .utf8) else {
      throw RocksDBLiteError.invalidEncoding
    }
    try delete(keyData)
  }
}

// MARK: - Error Type

/// Errors for RocksDBLite operations
public enum RocksDBLiteError: Error, Sendable {
  case openFailed(String)
  case databaseClosed
  case operationFailed(String)
  case invalidEncoding
}

extension RocksDBLiteError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .openFailed(let message):
      return "Failed to open database: \(message)"
    case .databaseClosed:
      return "Database is closed"
    case .operationFailed(let message):
      return "Operation failed: \(message)"
    case .invalidEncoding:
      return "Invalid UTF-8 encoding"
    }
  }
}
