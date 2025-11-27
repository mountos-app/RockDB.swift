//
//  RocksDBIterator.swift
//  RocksDB.swift
//
//  Iterator for RocksDB key-value scanning
//

import Foundation
import CRocksDB

/// Iterator for scanning RocksDB key-value pairs
public final class RocksDBIterator: @unchecked Sendable {
  private var handle: RocksDBIteratorRef?
  private let lock = NSRecursiveLock()

  internal init(handle: RocksDBIteratorRef) {
    self.handle = handle
  }

  deinit {
    close()
  }

  /// Close the iterator
  public func close() {
    lock.withLock {
      if let h = handle {
        rocksdb_iterator_destroy(h)
        handle = nil
      }
    }
  }

  // MARK: - Validity

  /// Whether the iterator is at a valid position
  public var isValid: Bool {
    lock.withLock {
      guard let h = handle else { return false }
      return rocksdb_iterator_valid(h) != 0
    }
  }

  // MARK: - Positioning

  /// Seek to the first key
  public func seekToFirst() {
    lock.withLock {
      guard let h = handle else { return }
      rocksdb_iterator_seek_to_first(h)
    }
  }

  /// Seek to the last key
  public func seekToLast() {
    lock.withLock {
      guard let h = handle else { return }
      rocksdb_iterator_seek_to_last(h)
    }
  }

  /// Seek to a specific key (or first key >= target)
  /// - Parameter key: Target key
  public func seek(to key: Data) {
    lock.withLock {
      guard let h = handle else { return }
      key.withUnsafeBytes { keyPtr in
        rocksdb_iterator_seek(h,
                              keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                              key.count)
      }
    }
  }

  /// Seek to a specific string key
  /// - Parameter key: Target key string
  public func seek(to key: String) {
    if let keyData = key.data(using: .utf8) {
      seek(to: keyData)
    }
  }

  /// Seek for previous key (last key <= target)
  /// - Parameter key: Target key
  public func seekForPrev(to key: Data) {
    lock.withLock {
      guard let h = handle else { return }
      key.withUnsafeBytes { keyPtr in
        rocksdb_iterator_seek_for_prev(h,
                                       keyPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                                       key.count)
      }
    }
  }

  // MARK: - Navigation

  /// Move to the next key
  public func next() {
    lock.withLock {
      guard let h = handle else { return }
      rocksdb_iterator_next(h)
    }
  }

  /// Move to the previous key
  public func prev() {
    lock.withLock {
      guard let h = handle else { return }
      rocksdb_iterator_prev(h)
    }
  }

  // MARK: - Current Key/Value

  /// Current key (nil if invalid)
  public var key: Data? {
    lock.withLock {
      guard let h = handle else { return nil }
      var keyLen: Int = 0
      guard let keyPtr = rocksdb_iterator_key(h, &keyLen) else {
        return nil
      }
      // Note: keyPtr is internal to iterator, don't free it
      return Data(bytes: keyPtr, count: keyLen)
    }
  }

  /// Current value (nil if invalid)
  public var value: Data? {
    lock.withLock {
      guard let h = handle else { return nil }
      var valueLen: Int = 0
      guard let valuePtr = rocksdb_iterator_value(h, &valueLen) else {
        return nil
      }
      // Note: valuePtr is internal to iterator, don't free it
      return Data(bytes: valuePtr, count: valueLen)
    }
  }

  /// Current key as string (nil if invalid or not valid UTF-8)
  public var keyString: String? {
    guard let keyData = key else { return nil }
    return String(data: keyData, encoding: .utf8)
  }

  /// Current value as string (nil if invalid or not valid UTF-8)
  public var valueString: String? {
    guard let valueData = value else { return nil }
    return String(data: valueData, encoding: .utf8)
  }

  /// Current key-value pair (nil if invalid)
  public var keyValue: (key: Data, value: Data)? {
    lock.withLock {
      guard let h = handle else { return nil }
      guard rocksdb_iterator_valid(h) != 0 else { return nil }

      var keyLen: Int = 0
      var valueLen: Int = 0

      guard let keyPtr = rocksdb_iterator_key(h, &keyLen),
            let valuePtr = rocksdb_iterator_value(h, &valueLen) else {
        return nil
      }

      return (
        key: Data(bytes: keyPtr, count: keyLen),
        value: Data(bytes: valuePtr, count: valueLen)
      )
    }
  }

  // MARK: - Status

  /// Check for errors during iteration
  /// - Throws: RocksDBError if an error occurred
  public func checkStatus() throws {
    let status = lock.withLock { () -> RocksDBStatus? in
      guard let h = handle else { return nil }
      return rocksdb_iterator_status(h)
    }

    if let status = status {
      try RocksDBError.check(status)
    }
  }
}

// MARK: - Sequence Conformance

extension RocksDBIterator: Sequence {
  public struct Iterator: IteratorProtocol {
    private let rocksIterator: RocksDBIterator
    private var started = false

    init(_ iterator: RocksDBIterator) {
      self.rocksIterator = iterator
    }

    public mutating func next() -> (key: Data, value: Data)? {
      if !started {
        started = true
        rocksIterator.seekToFirst()
      } else {
        rocksIterator.next()
      }

      return rocksIterator.keyValue
    }
  }

  public func makeIterator() -> Iterator {
    Iterator(self)
  }
}
