//
//  RocksDBBatch.swift
//  RocksDB.swift
//
//  Atomic write batch for RocksDB
//

import Foundation
import CRocksDB

/// Atomic batch of write operations
public final class RocksDBBatch: @unchecked Sendable {
  internal let handle: RocksDBBatchRef
  private let lock = NSRecursiveLock()

  /// Create a new empty batch
  public init() {
    self.handle = rocksdb_batch_create()
  }

  deinit {
    rocksdb_batch_destroy(handle)
  }

  // MARK: - Operations

  /// Add a put operation to the batch
  /// - Parameters:
  ///   - value: Value data
  ///   - key: Key data
  public func put(_ value: Data, forKey key: Data) {
    lock.withLock {
      key.withUnsafeBytes { keyPtr in
        value.withUnsafeBytes { valuePtr in
          rocksdb_batch_put(handle,
                            keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                            key.count,
                            valuePtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                            value.count)
        }
      }
    }
  }

  /// Add a put operation with string key and value
  /// - Parameters:
  ///   - value: String value
  ///   - key: String key
  public func put(_ value: String, forKey key: String) {
    if let keyData = key.data(using: .utf8),
       let valueData = value.data(using: .utf8) {
      put(valueData, forKey: keyData)
    }
  }

  /// Add a delete operation to the batch
  /// - Parameter key: Key to delete
  public func delete(_ key: Data) {
    lock.withLock {
      key.withUnsafeBytes { keyPtr in
        rocksdb_batch_delete(handle,
                             keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                             key.count)
      }
    }
  }

  /// Add a delete operation with string key
  /// - Parameter key: String key to delete
  public func delete(_ key: String) {
    if let keyData = key.data(using: .utf8) {
      delete(keyData)
    }
  }

  /// Add a delete range operation to the batch
  /// - Parameters:
  ///   - startKey: Start of range (inclusive)
  ///   - endKey: End of range (exclusive)
  public func deleteRange(from startKey: Data, to endKey: Data) {
    lock.withLock {
      startKey.withUnsafeBytes { startPtr in
        endKey.withUnsafeBytes { endPtr in
          rocksdb_batch_delete_range(handle,
                                     startPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                     startKey.count,
                                     endPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                     endKey.count)
        }
      }
    }
  }

  /// Clear all operations from the batch
  public func clear() {
    lock.withLock {
      rocksdb_batch_clear(handle)
    }
  }

  // MARK: - Properties

  /// Number of operations in the batch
  public var count: Int {
    lock.withLock {
      rocksdb_batch_count(handle)
    }
  }

  /// Size of batch data in bytes
  public var dataSize: Int {
    lock.withLock {
      rocksdb_batch_data_size(handle)
    }
  }

  /// Whether the batch is empty
  public var isEmpty: Bool {
    count == 0
  }
}
