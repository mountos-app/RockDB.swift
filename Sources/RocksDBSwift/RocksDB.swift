//
//  RocksDB.swift
//  RocksDB.swift
//
//  Main RocksDB database wrapper
//

import Foundation
import CRocksDB

/// Thread-safe RocksDB database wrapper
public final class RocksDB: @unchecked Sendable {
  private var handle: RocksDBRef?
  private let lock = NSRecursiveLock()

  /// Database path
  public let path: String

  /// Whether database supports transactions
  public let isTransactional: Bool

  /// Whether database is open
  public var isOpen: Bool {
    lock.withLock { handle != nil }
  }

  // MARK: - Initialization

  private init(handle: RocksDBRef, path: String, isTransactional: Bool) {
    self.handle = handle
    self.path = path
    self.isTransactional = isTransactional
  }

  deinit {
    close()
  }

  // MARK: - Factory Methods

  /// Open a RocksDB database
  /// - Parameters:
  ///   - path: Path to database directory
  ///   - options: Database options (default options if nil)
  /// - Returns: Open database instance
  /// - Throws: RocksDBError on failure
  public static func open(at path: String, options: RocksDBOptions = .default) throws -> RocksDB {
    let opts = options.createHandle()
    defer { rocksdb_options_destroy(opts) }

    var dbHandle: RocksDBRef?
    let status = rocksdb_open(path, opts, &dbHandle)
    try RocksDBError.check(status)

    guard let handle = dbHandle else {
      throw RocksDBError.ioError("Failed to open database")
    }

    return RocksDB(handle: handle, path: path, isTransactional: false)
  }

  /// Open a RocksDB database in read-only mode
  /// - Parameters:
  ///   - path: Path to database directory
  ///   - options: Database options
  ///   - errorIfWALExists: Error if write-ahead log exists
  /// - Returns: Open database instance
  /// - Throws: RocksDBError on failure
  public static func openReadOnly(
    at path: String,
    options: RocksDBOptions = .default,
    errorIfWALExists: Bool = false
  ) throws -> RocksDB {
    let opts = options.createHandle()
    defer { rocksdb_options_destroy(opts) }

    var dbHandle: RocksDBRef?
    let status = rocksdb_open_for_read_only(path, opts, errorIfWALExists ? 1 : 0, &dbHandle)
    try RocksDBError.check(status)

    guard let handle = dbHandle else {
      throw RocksDBError.ioError("Failed to open database")
    }

    return RocksDB(handle: handle, path: path, isTransactional: false)
  }

  /// Open a RocksDB database with optimistic transaction support
  /// - Parameters:
  ///   - path: Path to database directory
  ///   - options: Database options
  /// - Returns: Open database instance with transaction support
  /// - Throws: RocksDBError on failure
  public static func openWithTransactions(
    at path: String,
    options: RocksDBOptions = .default
  ) throws -> RocksDB {
    let opts = options.createHandle()
    defer { rocksdb_options_destroy(opts) }

    var dbHandle: RocksDBRef?
    let status = rocksdb_open_transactional(path, opts, &dbHandle)
    try RocksDBError.check(status)

    guard let handle = dbHandle else {
      throw RocksDBError.ioError("Failed to open transactional database")
    }

    return RocksDB(handle: handle, path: path, isTransactional: true)
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
  ///   - options: Write options
  /// - Throws: RocksDBError on failure
  public func put(_ value: Data, forKey key: Data, options: RocksDBWriteOptions = .default) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      let writeOpts = options.createHandle()
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
      try RocksDBError.check(status)
    }
  }

  /// Get value for key
  /// - Parameters:
  ///   - key: Key data
  ///   - options: Read options
  /// - Returns: Value data or nil if not found
  /// - Throws: RocksDBError on failure
  public func get(_ key: Data, options: RocksDBReadOptions = .default) throws -> Data? {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      let readOpts = options.createHandle()
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

      // NotFound is not an error, just return nil
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

  /// Delete a key
  /// - Parameters:
  ///   - key: Key data
  ///   - options: Write options
  /// - Throws: RocksDBError on failure
  public func delete(_ key: Data, options: RocksDBWriteOptions = .default) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      let writeOpts = options.createHandle()
      defer { rocksdb_write_options_destroy(writeOpts) }

      let status = key.withUnsafeBytes { keyPtr in
        rocksdb_delete(h, writeOpts,
                       keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                       key.count)
      }
      try RocksDBError.check(status)
    }
  }

  /// Check if key may exist (bloom filter check, may have false positives)
  /// - Parameters:
  ///   - key: Key data
  ///   - options: Read options
  /// - Returns: true if key may exist
  public func keyMayExist(_ key: Data, options: RocksDBReadOptions = .default) -> Bool {
    lock.withLock {
      guard let h = handle else {
        return false
      }

      let readOpts = options.createHandle()
      defer { rocksdb_read_options_destroy(readOpts) }

      return key.withUnsafeBytes { keyPtr in
        rocksdb_key_may_exist(h, readOpts,
                              keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                              key.count) != 0
      }
    }
  }

  // MARK: - String Convenience Methods

  /// Put string value for string key
  public func put(_ value: String, forKey key: String, options: RocksDBWriteOptions = .default) throws {
    guard let keyData = key.data(using: .utf8),
          let valueData = value.data(using: .utf8) else {
      throw RocksDBError.invalidArgument("Invalid UTF-8 encoding")
    }
    try put(valueData, forKey: keyData, options: options)
  }

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

  /// Delete string key
  public func delete(_ key: String, options: RocksDBWriteOptions = .default) throws {
    guard let keyData = key.data(using: .utf8) else {
      throw RocksDBError.invalidArgument("Invalid key encoding")
    }
    try delete(keyData, options: options)
  }

  // MARK: - Batch Operations

  /// Execute a batch of operations atomically
  /// - Parameters:
  ///   - options: Write options
  ///   - operations: Closure receiving a batch to add operations to
  /// - Throws: RocksDBError on failure
  public func batch(
    options: RocksDBWriteOptions = .default,
    _ operations: (RocksDBBatch) throws -> Void
  ) throws {
    let batch = RocksDBBatch()
    try operations(batch)
    try writeBatch(batch, options: options)
  }

  /// Write a batch to the database
  /// - Parameters:
  ///   - batch: Batch to write
  ///   - options: Write options
  /// - Throws: RocksDBError on failure
  public func writeBatch(_ batch: RocksDBBatch, options: RocksDBWriteOptions = .default) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      let writeOpts = options.createHandle()
      defer { rocksdb_write_options_destroy(writeOpts) }

      let status = rocksdb_write_batch(h, writeOpts, batch.handle)
      try RocksDBError.check(status)
    }
  }

  // MARK: - Transaction Operations

  /// Execute a transaction with automatic commit/rollback
  /// - Parameters:
  ///   - options: Write options for the transaction
  ///   - operation: Closure receiving a transaction to perform operations
  /// - Returns: Result of the operation closure
  /// - Throws: RocksDBError on failure or if not a transactional database
  public func transaction<T>(
    options: RocksDBWriteOptions = .default,
    _ operation: (RocksDBTransaction) throws -> T
  ) throws -> T {
    guard isTransactional else {
      throw RocksDBError.notSupported("Database not opened with transaction support")
    }

    let txn = try beginTransaction(options: options)

    do {
      let result = try operation(txn)
      try txn.commit()
      return result
    } catch {
      txn.rollback()
      throw error
    }
  }

  /// Begin a new transaction
  /// - Parameter options: Write options for the transaction
  /// - Returns: New transaction
  /// - Throws: RocksDBError on failure
  public func beginTransaction(options: RocksDBWriteOptions = .default) throws -> RocksDBTransaction {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      guard isTransactional else {
        throw RocksDBError.notSupported("Database not opened with transaction support")
      }

      let writeOpts = options.createHandle()
      defer { rocksdb_write_options_destroy(writeOpts) }

      guard let txnHandle = rocksdb_transaction_begin(h, writeOpts) else {
        throw RocksDBError.ioError("Failed to begin transaction")
      }

      return RocksDBTransaction(handle: txnHandle)
    }
  }

  // MARK: - Iterator Operations

  /// Create an iterator for the database
  /// - Parameter options: Read options
  /// - Returns: Database iterator
  /// - Throws: RocksDBError on failure
  public func makeIterator(options: RocksDBReadOptions = .default) throws -> RocksDBIterator {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      let readOpts = options.createHandle()
      defer { rocksdb_read_options_destroy(readOpts) }

      guard let iterHandle = rocksdb_iterator_create(h, readOpts) else {
        throw RocksDBError.ioError("Failed to create iterator")
      }

      return RocksDBIterator(handle: iterHandle)
    }
  }

  /// Iterate over all key-value pairs
  /// - Parameter body: Closure called for each key-value pair, return false to stop
  /// - Throws: RocksDBError on failure
  public func forEach(_ body: (Data, Data) throws -> Bool) throws {
    let iter = try makeIterator()
    defer { iter.close() }

    iter.seekToFirst()
    while iter.isValid {
      guard let key = iter.key, let value = iter.value else { break }
      if try !body(key, value) { break }
      iter.next()
    }
    try iter.checkStatus()
  }

  /// Iterate over key-value pairs with a key prefix
  /// - Parameters:
  ///   - prefix: Key prefix to match
  ///   - body: Closure called for each matching key-value pair, return false to stop
  /// - Throws: RocksDBError on failure
  public func forEachWithPrefix(_ prefix: Data, _ body: (Data, Data) throws -> Bool) throws {
    let iter = try makeIterator()
    defer { iter.close() }

    iter.seek(to: prefix)
    while iter.isValid {
      guard let key = iter.key, let value = iter.value else { break }
      // Check prefix match
      guard key.count >= prefix.count && key.prefix(prefix.count) == prefix else { break }
      if try !body(key, value) { break }
      iter.next()
    }
    try iter.checkStatus()
  }

  // MARK: - Maintenance Operations

  /// Compact a range of keys
  /// - Parameters:
  ///   - startKey: Start of range (nil for beginning)
  ///   - endKey: End of range (nil for end)
  /// - Throws: RocksDBError on failure
  public func compactRange(from startKey: Data? = nil, to endKey: Data? = nil) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      let status: RocksDBStatus

      if let start = startKey, let end = endKey {
        status = start.withUnsafeBytes { startPtr in
          end.withUnsafeBytes { endPtr in
            rocksdb_compact_range(h,
                                  startPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                  start.count,
                                  endPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                  end.count)
          }
        }
      } else if let start = startKey {
        status = start.withUnsafeBytes { startPtr in
          rocksdb_compact_range(h,
                                startPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                start.count,
                                nil, 0)
        }
      } else if let end = endKey {
        status = end.withUnsafeBytes { endPtr in
          rocksdb_compact_range(h, nil, 0,
                                endPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                end.count)
        }
      } else {
        status = rocksdb_compact_range(h, nil, 0, nil, 0)
      }

      try RocksDBError.check(status)
    }
  }

  /// Flush the database
  /// - Parameter wait: Wait for flush to complete
  /// - Throws: RocksDBError on failure
  public func flush(wait: Bool = true) throws {
    try lock.withLock {
      guard let h = handle else {
        throw RocksDBError.databaseClosed
      }

      let status = rocksdb_flush(h, wait ? 1 : 0)
      try RocksDBError.check(status)
    }
  }

  /// Get a database property value
  /// - Parameter name: Property name (e.g., "rocksdb.estimate-num-keys")
  /// - Returns: Property value or nil if not found
  public func getProperty(_ name: String) -> String? {
    lock.withLock {
      guard let h = handle else {
        return nil
      }

      guard let ptr = rocksdb_get_property(h, name) else {
        return nil
      }
      defer { rocksdb_free_string(ptr) }

      return String(cString: ptr)
    }
  }

  /// Estimated number of keys in the database
  public var estimatedKeyCount: Int? {
    guard let value = getProperty("rocksdb.estimate-num-keys"),
          let count = Int(value) else {
      return nil
    }
    return count
  }

  /// Current memory usage statistics
  public var memoryUsage: String? {
    getProperty("rocksdb.cur-size-all-mem-tables")
  }
}
