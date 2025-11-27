//
//  RocksDBTransaction.swift
//  RocksDB.swift
//
//  Optimistic transaction for RocksDB
//

import Foundation
import CRocksDB

/// Optimistic transaction providing snapshot isolation
public final class RocksDBTransaction: @unchecked Sendable {
  private var handle: RocksDBTransactionRef?
  private let lock = NSRecursiveLock()
  private var committed = false

  internal init(handle: RocksDBTransactionRef) {
    self.handle = handle
  }

  deinit {
    // If not committed, rollback
    if !committed {
      rollback()
    }
    destroy()
  }

  private func destroy() {
    lock.withLock {
      if let h = handle {
        rocksdb_transaction_destroy(h)
        handle = nil
      }
    }
  }

  // MARK: - Read Operations

  /// Get value for key within the transaction
  /// - Parameters:
  ///   - key: Key data
  ///   - options: Read options
  /// - Returns: Value data or nil if not found
  /// - Throws: RocksDBError on failure
  public func get(_ key: Data, options: RocksDBReadOptions = .default) throws -> Data? {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.invalidArgument("Transaction is closed")
      }

      let readOpts = options.createHandle()
      defer { rocksdb_read_options_destroy(readOpts) }

      var valuePtr: UnsafeMutablePointer<CChar>?
      var valueLen: Int = 0

      let status = key.withUnsafeBytes { keyPtr in
        rocksdb_transaction_get(h, readOpts,
                                keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                key.count,
                                &valuePtr,
                                &valueLen)
      }

      // NotFound is not an error
      if status.code == RocksDBStatusNotFound {
        if let msg = status.message {
          rocksdb_free_string(msg)
        }
        return nil
      }

      try RocksDBError.check(status)

      guard let ptr = valuePtr else {
        return nil
      }
      defer { rocksdb_free_data(ptr) }

      return Data(bytes: ptr, count: valueLen)
    }
  }

  /// Get value for key with exclusive lock (for read-modify-write patterns)
  /// - Parameters:
  ///   - key: Key data
  ///   - options: Read options
  /// - Returns: Value data or nil if not found
  /// - Throws: RocksDBError on failure
  public func getForUpdate(_ key: Data, options: RocksDBReadOptions = .default) throws -> Data? {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.invalidArgument("Transaction is closed")
      }

      let readOpts = options.createHandle()
      defer { rocksdb_read_options_destroy(readOpts) }

      var valuePtr: UnsafeMutablePointer<CChar>?
      var valueLen: Int = 0

      let status = key.withUnsafeBytes { keyPtr in
        rocksdb_transaction_get_for_update(h, readOpts,
                                           keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                           key.count,
                                           &valuePtr,
                                           &valueLen)
      }

      // NotFound is not an error
      if status.code == RocksDBStatusNotFound {
        if let msg = status.message {
          rocksdb_free_string(msg)
        }
        return nil
      }

      try RocksDBError.check(status)

      guard let ptr = valuePtr else {
        return nil
      }
      defer { rocksdb_free_data(ptr) }

      return Data(bytes: ptr, count: valueLen)
    }
  }

  // MARK: - Write Operations

  /// Put a key-value pair within the transaction
  /// - Parameters:
  ///   - value: Value data
  ///   - key: Key data
  /// - Throws: RocksDBError on failure
  public func put(_ value: Data, forKey key: Data) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.invalidArgument("Transaction is closed")
      }

      let status = key.withUnsafeBytes { keyPtr in
        value.withUnsafeBytes { valuePtr in
          rocksdb_transaction_put(h,
                                  keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                  key.count,
                                  valuePtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                  value.count)
        }
      }
      try RocksDBError.check(status)
    }
  }

  /// Put string value for string key within the transaction
  public func put(_ value: String, forKey key: String) throws {
    guard let keyData = key.data(using: .utf8),
          let valueData = value.data(using: .utf8) else {
      throw RocksDBError.invalidArgument("Invalid UTF-8 encoding")
    }
    try put(valueData, forKey: keyData)
  }

  /// Delete a key within the transaction
  /// - Parameter key: Key data
  /// - Throws: RocksDBError on failure
  public func delete(_ key: Data) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.invalidArgument("Transaction is closed")
      }

      let status = key.withUnsafeBytes { keyPtr in
        rocksdb_transaction_delete(h,
                                   keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                   key.count)
      }
      try RocksDBError.check(status)
    }
  }

  /// Delete string key within the transaction
  public func delete(_ key: String) throws {
    guard let keyData = key.data(using: .utf8) else {
      throw RocksDBError.invalidArgument("Invalid key encoding")
    }
    try delete(keyData)
  }

  // MARK: - String Convenience Methods

  /// Get string value for string key
  public func getString(_ key: String, options: RocksDBReadOptions = .default) throws -> String? {
    guard let keyData = key.data(using: .utf8) else {
      throw RocksDBError.invalidArgument("Invalid key encoding")
    }
    guard let data = try get(keyData, options: options) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  // MARK: - Iterator

  /// Create an iterator within the transaction
  /// - Parameter options: Read options
  /// - Returns: Transaction iterator
  /// - Throws: RocksDBError on failure
  public func makeIterator(options: RocksDBReadOptions = .default) throws -> RocksDBIterator {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.invalidArgument("Transaction is closed")
      }

      let readOpts = options.createHandle()
      defer { rocksdb_read_options_destroy(readOpts) }

      guard let iterHandle = rocksdb_transaction_create_iterator(h, readOpts) else {
        throw RocksDBError.ioError("Failed to create transaction iterator")
      }

      return RocksDBIterator(handle: iterHandle)
    }
  }

  // MARK: - Commit / Rollback

  /// Commit the transaction
  /// - Throws: RocksDBError on failure (e.g., conflict detected)
  public func commit() throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.invalidArgument("Transaction is closed")
      }

      let status = rocksdb_transaction_commit(h)

      // Check for transaction conflicts
      if status.code == RocksDBStatusBusy || status.code == RocksDBStatusTryAgain {
        let message = status.message.map { String(cString: $0) } ?? "Transaction conflict"
        if let msg = status.message {
          rocksdb_free_string(msg)
        }
        throw RocksDBError.transactionConflict(message)
      }

      try RocksDBError.check(status)
      committed = true
    }
  }

  /// Rollback the transaction
  public func rollback() {
    lock.withLock {
      guard let h = handle else { return }
      rocksdb_transaction_rollback(h)
    }
  }

  // MARK: - Savepoints

  /// Set a savepoint for partial rollback
  public func setSavepoint() {
    lock.withLock {
      guard let h = handle else { return }
      rocksdb_transaction_set_savepoint(h)
    }
  }

  /// Rollback to the last savepoint
  /// - Throws: RocksDBError on failure
  public func rollbackToSavepoint() throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.invalidArgument("Transaction is closed")
      }

      let status = rocksdb_transaction_rollback_to_savepoint(h)
      try RocksDBError.check(status)
    }
  }
}
