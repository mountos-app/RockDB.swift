//
//  RocksDBError.swift
//  RocksDB.swift
//
//  Error types for RocksDB operations
//

import Foundation
import CRocksDB

/// Error types for RocksDB operations
public enum RocksDBError: Error, LocalizedError, Sendable {
  case notFound
  case corruption(String)
  case notSupported(String)
  case invalidArgument(String)
  case ioError(String)
  case mergeInProgress(String)
  case incomplete(String)
  case shutdownInProgress
  case timedOut
  case aborted(String)
  case busy
  case expired
  case tryAgain
  case compactionTooLarge(String)
  case databaseClosed
  case transactionConflict(String)

  public var errorDescription: String? {
    switch self {
    case .notFound:
      return "Key not found"
    case .corruption(let msg):
      return "Database corruption: \(msg)"
    case .notSupported(let msg):
      return "Operation not supported: \(msg)"
    case .invalidArgument(let msg):
      return "Invalid argument: \(msg)"
    case .ioError(let msg):
      return "I/O error: \(msg)"
    case .mergeInProgress(let msg):
      return "Merge in progress: \(msg)"
    case .incomplete(let msg):
      return "Operation incomplete: \(msg)"
    case .shutdownInProgress:
      return "Database shutdown in progress"
    case .timedOut:
      return "Operation timed out"
    case .aborted(let msg):
      return "Operation aborted: \(msg)"
    case .busy:
      return "Database busy"
    case .expired:
      return "Operation expired"
    case .tryAgain:
      return "Try again"
    case .compactionTooLarge(let msg):
      return "Compaction too large: \(msg)"
    case .databaseClosed:
      return "Database is closed"
    case .transactionConflict(let msg):
      return "Transaction conflict: \(msg)"
    }
  }

  /// Create error from RocksDB C status
  static func from(_ status: RocksDBStatus) -> RocksDBError? {
    guard status.code != RocksDBStatusOK else { return nil }

    let message: String
    if let msg = status.message {
      message = String(cString: msg)
    } else {
      message = "Unknown error"
    }

    switch status.code {
    case RocksDBStatusNotFound:
      return .notFound
    case RocksDBStatusCorruption:
      return .corruption(message)
    case RocksDBStatusNotSupported:
      return .notSupported(message)
    case RocksDBStatusInvalidArgument:
      return .invalidArgument(message)
    case RocksDBStatusIOError:
      return .ioError(message)
    case RocksDBStatusMergeInProgress:
      return .mergeInProgress(message)
    case RocksDBStatusIncomplete:
      return .incomplete(message)
    case RocksDBStatusShutdownInProgress:
      return .shutdownInProgress
    case RocksDBStatusTimedOut:
      return .timedOut
    case RocksDBStatusAborted:
      return .aborted(message)
    case RocksDBStatusBusy:
      return .busy
    case RocksDBStatusExpired:
      return .expired
    case RocksDBStatusTryAgain:
      return .tryAgain
    case RocksDBStatusCompactionTooLarge:
      return .compactionTooLarge(message)
    default:
      return .ioError(message)
    }
  }

  /// Check status and throw if error
  static func check(_ status: RocksDBStatus) throws {
    if let error = from(status) {
      // Free the message string if present
      if let msg = status.message {
        rocksdb_free_string(msg)
      }
      throw error
    }
  }

  /// Check status, returning nil for NotFound (for get operations)
  static func checkForGet(_ status: RocksDBStatus) throws {
    if status.code == RocksDBStatusNotFound {
      // Free message if present
      if let msg = status.message {
        rocksdb_free_string(msg)
      }
      return // Not found is not an error for get
    }
    try check(status)
  }
}
