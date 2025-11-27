//
//  RocksDBOptions.swift
//  RocksDB.swift
//
//  Configuration options for RocksDB
//

import Foundation
import CRocksDB

// MARK: - Compression Type

/// Compression algorithms supported by RocksDB
public enum RocksDBCompression: Int32, Sendable {
  case none = 0
  case snappy = 1
  case zlib = 2
  case bz2 = 3
  case lz4 = 4
  case lz4hc = 5
  case xpress = 6
  case zstd = 7
}

// MARK: - Database Options

/// Configuration options for opening a RocksDB database
public struct RocksDBOptions: Sendable {
  /// Create database if it doesn't exist (default: true)
  public var createIfMissing: Bool = true

  /// Error if database already exists (default: false)
  public var errorIfExists: Bool = false

  /// Enable paranoid checks (default: false)
  public var paranoidChecks: Bool = false

  /// Compression algorithm (default: lz4)
  public var compression: RocksDBCompression = .lz4

  /// Write buffer size in bytes (default: 64MB)
  public var writeBufferSize: Int = 64 * 1024 * 1024

  /// Maximum number of write buffers (default: 3)
  public var maxWriteBufferNumber: Int = 3

  /// Maximum number of open files (default: 1000, -1 for unlimited)
  public var maxOpenFiles: Int = 1000

  /// Maximum background compaction threads (default: 2)
  public var maxBackgroundCompactions: Int = 2

  /// Maximum background flush threads (default: 1)
  public var maxBackgroundFlushes: Int = 1

  /// Level-0 file number compaction trigger (default: 4)
  public var level0FileNumCompactionTrigger: Int = 4

  /// Level-0 slowdown writes trigger (default: 20)
  public var level0SlowdownWritesTrigger: Int = 20

  /// Level-0 stop writes trigger (default: 36)
  public var level0StopWritesTrigger: Int = 36

  /// Target file size base in bytes (default: 64MB)
  public var targetFileSizeBase: UInt64 = 64 * 1024 * 1024

  /// Max bytes for level base (default: 256MB)
  public var maxBytesForLevelBase: UInt64 = 256 * 1024 * 1024

  /// Enable statistics collection (default: false)
  public var enableStatistics: Bool = false

  /// Optimize for point lookups with given block cache size in MB
  public var optimizeForPointLookup: UInt64? = nil

  /// Optimize for level-style compaction with given memtable memory budget
  public var optimizeLevelStyleCompaction: UInt64? = nil

  public init() {}

  /// Default options
  public static var `default`: RocksDBOptions {
    RocksDBOptions()
  }

  /// Options optimized for point lookups (get operations)
  public static func pointLookup(blockCacheSizeMB: UInt64 = 128) -> RocksDBOptions {
    var opts = RocksDBOptions()
    opts.optimizeForPointLookup = blockCacheSizeMB
    return opts
  }

  /// Options optimized for bulk loading
  public static var bulkLoad: RocksDBOptions {
    var opts = RocksDBOptions()
    opts.writeBufferSize = 256 * 1024 * 1024
    opts.maxWriteBufferNumber = 6
    opts.level0FileNumCompactionTrigger = 8
    opts.level0SlowdownWritesTrigger = 16
    opts.level0StopWritesTrigger = 24
    return opts
  }

  /// Create C handle from options
  internal func createHandle() -> RocksDBOptionsRef {
    let opts = rocksdb_options_create()!

    rocksdb_options_set_create_if_missing(opts, createIfMissing ? 1 : 0)
    rocksdb_options_set_error_if_exists(opts, errorIfExists ? 1 : 0)
    rocksdb_options_set_paranoid_checks(opts, paranoidChecks ? 1 : 0)
    rocksdb_options_set_compression(opts, compression.rawValue)
    rocksdb_options_set_write_buffer_size(opts, writeBufferSize)
    rocksdb_options_set_max_write_buffer_number(opts, Int32(maxWriteBufferNumber))
    rocksdb_options_set_max_open_files(opts, Int32(maxOpenFiles))
    rocksdb_options_set_max_background_compactions(opts, Int32(maxBackgroundCompactions))
    rocksdb_options_set_max_background_flushes(opts, Int32(maxBackgroundFlushes))
    rocksdb_options_set_level0_file_num_compaction_trigger(opts, Int32(level0FileNumCompactionTrigger))
    rocksdb_options_set_level0_slowdown_writes_trigger(opts, Int32(level0SlowdownWritesTrigger))
    rocksdb_options_set_level0_stop_writes_trigger(opts, Int32(level0StopWritesTrigger))
    rocksdb_options_set_target_file_size_base(opts, targetFileSizeBase)
    rocksdb_options_set_max_bytes_for_level_base(opts, maxBytesForLevelBase)

    if enableStatistics {
      rocksdb_options_enable_statistics(opts)
    }

    if let pointLookupSize = optimizeForPointLookup {
      rocksdb_options_optimize_for_point_lookup(opts, pointLookupSize)
    }

    if let levelStyleBudget = optimizeLevelStyleCompaction {
      rocksdb_options_optimize_level_style_compaction(opts, levelStyleBudget)
    }

    return opts
  }
}

// MARK: - Read Options

/// Options for read operations
public struct RocksDBReadOptions: Sendable {
  /// Verify checksums on read (default: true)
  public var verifyChecksums: Bool = true

  /// Fill block cache on read (default: true)
  public var fillCache: Bool = true

  /// Use prefix same as start for iteration (default: false)
  public var prefixSameAsStart: Bool = false

  public init() {}

  /// Default read options
  public static var `default`: RocksDBReadOptions {
    RocksDBReadOptions()
  }

  /// Create C handle from options
  internal func createHandle() -> RocksDBReadOptionsRef {
    let opts = rocksdb_read_options_create()!
    rocksdb_read_options_set_verify_checksums(opts, verifyChecksums ? 1 : 0)
    rocksdb_read_options_set_fill_cache(opts, fillCache ? 1 : 0)
    rocksdb_read_options_set_prefix_same_as_start(opts, prefixSameAsStart ? 1 : 0)
    return opts
  }
}

// MARK: - Write Options

/// Options for write operations
public struct RocksDBWriteOptions: Sendable {
  /// Sync write to disk (default: false)
  public var sync: Bool = false

  /// Disable write-ahead log (default: false)
  public var disableWAL: Bool = false

  public init() {}

  /// Default write options
  public static var `default`: RocksDBWriteOptions {
    RocksDBWriteOptions()
  }

  /// Sync write options (fsync after write)
  public static var sync: RocksDBWriteOptions {
    var opts = RocksDBWriteOptions()
    opts.sync = true
    return opts
  }

  /// Create C handle from options
  internal func createHandle() -> RocksDBWriteOptionsRef {
    let opts = rocksdb_write_options_create()!
    rocksdb_write_options_set_sync(opts, sync ? 1 : 0)
    rocksdb_write_options_disable_wal(opts, disableWAL ? 1 : 0)
    return opts
  }
}
