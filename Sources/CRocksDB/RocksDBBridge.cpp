//
//  RocksDBBridge.cpp
//  RocksDB.swift
//
//  C bridge implementation for RocksDB C++ API
//

#include "include/RocksDBBridge.h"

#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/slice.h>
#include <rocksdb/statistics.h>
#include <rocksdb/status.h>
#include <rocksdb/iterator.h>
#include <rocksdb/write_batch.h>
#include <rocksdb/utilities/optimistic_transaction_db.h>
#include <rocksdb/utilities/transaction.h>

#include <cstring>
#include <memory>
#include <string>

// =============================================================================
// MARK: - Internal Handle Structures
// =============================================================================

struct RocksDBHandle {
  rocksdb::DB* db = nullptr;
  rocksdb::OptimisticTransactionDB* txn_db = nullptr;
  bool is_transactional = false;

  ~RocksDBHandle() {
    if (is_transactional && txn_db) {
      delete txn_db;
    } else if (db) {
      delete db;
    }
  }
};

struct RocksDBIteratorHandle {
  rocksdb::Iterator* iter = nullptr;

  ~RocksDBIteratorHandle() {
    delete iter;
  }
};

struct RocksDBBatchHandle {
  rocksdb::WriteBatch batch;
};

struct RocksDBTransactionHandle {
  rocksdb::Transaction* txn = nullptr;

  ~RocksDBTransactionHandle() {
    delete txn;
  }
};

struct RocksDBOptionsHandle {
  rocksdb::Options options;
};

struct RocksDBReadOptionsHandle {
  rocksdb::ReadOptions options;
};

struct RocksDBWriteOptionsHandle {
  rocksdb::WriteOptions options;
};

struct RocksDBSnapshotHandle {
  const rocksdb::Snapshot* snapshot = nullptr;
};

// =============================================================================
// MARK: - Helper Functions
// =============================================================================

static RocksDBStatus make_status(const rocksdb::Status& s) {
  RocksDBStatus result;

  if (s.ok()) {
    result.code = RocksDBStatusOK;
    result.message = nullptr;
    return result;
  }

  // Map status codes
  if (s.IsNotFound()) {
    result.code = RocksDBStatusNotFound;
  } else if (s.IsCorruption()) {
    result.code = RocksDBStatusCorruption;
  } else if (s.IsNotSupported()) {
    result.code = RocksDBStatusNotSupported;
  } else if (s.IsInvalidArgument()) {
    result.code = RocksDBStatusInvalidArgument;
  } else if (s.IsIOError()) {
    result.code = RocksDBStatusIOError;
  } else if (s.IsMergeInProgress()) {
    result.code = RocksDBStatusMergeInProgress;
  } else if (s.IsIncomplete()) {
    result.code = RocksDBStatusIncomplete;
  } else if (s.IsShutdownInProgress()) {
    result.code = RocksDBStatusShutdownInProgress;
  } else if (s.IsTimedOut()) {
    result.code = RocksDBStatusTimedOut;
  } else if (s.IsAborted()) {
    result.code = RocksDBStatusAborted;
  } else if (s.IsBusy()) {
    result.code = RocksDBStatusBusy;
  } else if (s.IsExpired()) {
    result.code = RocksDBStatusExpired;
  } else if (s.IsTryAgain()) {
    result.code = RocksDBStatusTryAgain;
  } else if (s.IsCompactionTooLarge()) {
    result.code = RocksDBStatusCompactionTooLarge;
  } else {
    result.code = RocksDBStatusIOError;
  }

  std::string msg = s.ToString();
  result.message = strdup(msg.c_str());
  return result;
}

static RocksDBStatus make_ok() {
  RocksDBStatus result;
  result.code = RocksDBStatusOK;
  result.message = nullptr;
  return result;
}

// =============================================================================
// MARK: - Memory Management
// =============================================================================

void rocksdb_free_string(char* str) {
  free(str);
}

void rocksdb_free_data(void* data) {
  free(data);
}

// =============================================================================
// MARK: - Database Options
// =============================================================================

RocksDBOptionsRef rocksdb_options_create(void) {
  return new RocksDBOptionsHandle();
}

void rocksdb_options_destroy(RocksDBOptionsRef opts) {
  delete opts;
}

void rocksdb_options_set_create_if_missing(RocksDBOptionsRef opts, int value) {
  opts->options.create_if_missing = (value != 0);
}

void rocksdb_options_set_error_if_exists(RocksDBOptionsRef opts, int value) {
  opts->options.error_if_exists = (value != 0);
}

void rocksdb_options_set_paranoid_checks(RocksDBOptionsRef opts, int value) {
  opts->options.paranoid_checks = (value != 0);
}

void rocksdb_options_set_compression(RocksDBOptionsRef opts, int type) {
  opts->options.compression = static_cast<rocksdb::CompressionType>(type);
}

void rocksdb_options_set_write_buffer_size(RocksDBOptionsRef opts, size_t size) {
  opts->options.write_buffer_size = size;
}

void rocksdb_options_set_max_write_buffer_number(RocksDBOptionsRef opts, int value) {
  opts->options.max_write_buffer_number = value;
}

void rocksdb_options_set_max_open_files(RocksDBOptionsRef opts, int value) {
  opts->options.max_open_files = value;
}

void rocksdb_options_set_max_background_compactions(RocksDBOptionsRef opts, int value) {
  opts->options.max_background_compactions = value;
}

void rocksdb_options_set_max_background_flushes(RocksDBOptionsRef opts, int value) {
  opts->options.max_background_flushes = value;
}

void rocksdb_options_set_level0_file_num_compaction_trigger(RocksDBOptionsRef opts, int value) {
  opts->options.level0_file_num_compaction_trigger = value;
}

void rocksdb_options_set_level0_slowdown_writes_trigger(RocksDBOptionsRef opts, int value) {
  opts->options.level0_slowdown_writes_trigger = value;
}

void rocksdb_options_set_level0_stop_writes_trigger(RocksDBOptionsRef opts, int value) {
  opts->options.level0_stop_writes_trigger = value;
}

void rocksdb_options_set_target_file_size_base(RocksDBOptionsRef opts, uint64_t size) {
  opts->options.target_file_size_base = size;
}

void rocksdb_options_set_max_bytes_for_level_base(RocksDBOptionsRef opts, uint64_t size) {
  opts->options.max_bytes_for_level_base = size;
}

void rocksdb_options_enable_statistics(RocksDBOptionsRef opts) {
  opts->options.statistics = rocksdb::CreateDBStatistics();
}

void rocksdb_options_optimize_for_point_lookup(RocksDBOptionsRef opts, uint64_t block_cache_size_mb) {
  opts->options.OptimizeForPointLookup(block_cache_size_mb);
}

void rocksdb_options_optimize_level_style_compaction(RocksDBOptionsRef opts, uint64_t memtable_memory_budget) {
  opts->options.OptimizeLevelStyleCompaction(memtable_memory_budget);
}

// =============================================================================
// MARK: - Read Options
// =============================================================================

RocksDBReadOptionsRef rocksdb_read_options_create(void) {
  return new RocksDBReadOptionsHandle();
}

void rocksdb_read_options_destroy(RocksDBReadOptionsRef opts) {
  delete opts;
}

void rocksdb_read_options_set_verify_checksums(RocksDBReadOptionsRef opts, int value) {
  opts->options.verify_checksums = (value != 0);
}

void rocksdb_read_options_set_fill_cache(RocksDBReadOptionsRef opts, int value) {
  opts->options.fill_cache = (value != 0);
}

void rocksdb_read_options_set_snapshot(RocksDBReadOptionsRef opts, RocksDBSnapshotRef snapshot) {
  opts->options.snapshot = snapshot ? snapshot->snapshot : nullptr;
}

void rocksdb_read_options_set_prefix_same_as_start(RocksDBReadOptionsRef opts, int value) {
  opts->options.prefix_same_as_start = (value != 0);
}

// =============================================================================
// MARK: - Write Options
// =============================================================================

RocksDBWriteOptionsRef rocksdb_write_options_create(void) {
  return new RocksDBWriteOptionsHandle();
}

void rocksdb_write_options_destroy(RocksDBWriteOptionsRef opts) {
  delete opts;
}

void rocksdb_write_options_set_sync(RocksDBWriteOptionsRef opts, int value) {
  opts->options.sync = (value != 0);
}

void rocksdb_write_options_disable_wal(RocksDBWriteOptionsRef opts, int value) {
  opts->options.disableWAL = (value != 0);
}

// =============================================================================
// MARK: - Database Operations
// =============================================================================

RocksDBStatus rocksdb_open(const char* path, RocksDBOptionsRef opts, RocksDBRef* db_out) {
  auto handle = new RocksDBHandle();
  rocksdb::Status s = rocksdb::DB::Open(opts->options, path, &handle->db);

  if (s.ok()) {
    *db_out = handle;
  } else {
    delete handle;
    *db_out = nullptr;
  }
  return make_status(s);
}

RocksDBStatus rocksdb_open_for_read_only(const char* path, RocksDBOptionsRef opts,
                                          int error_if_wal_exists, RocksDBRef* db_out) {
  auto handle = new RocksDBHandle();
  rocksdb::Status s = rocksdb::DB::OpenForReadOnly(opts->options, path, &handle->db,
                                                    error_if_wal_exists != 0);

  if (s.ok()) {
    *db_out = handle;
  } else {
    delete handle;
    *db_out = nullptr;
  }
  return make_status(s);
}

RocksDBStatus rocksdb_open_transactional(const char* path, RocksDBOptionsRef opts, RocksDBRef* db_out) {
  auto handle = new RocksDBHandle();
  handle->is_transactional = true;

  rocksdb::Status s = rocksdb::OptimisticTransactionDB::Open(
    opts->options, path, &handle->txn_db);

  if (s.ok()) {
    handle->db = handle->txn_db->GetBaseDB();
    *db_out = handle;
  } else {
    delete handle;
    *db_out = nullptr;
  }
  return make_status(s);
}

void rocksdb_close(RocksDBRef db) {
  delete db;
}

int rocksdb_is_transactional(RocksDBRef db) {
  return db && db->is_transactional ? 1 : 0;
}

// =============================================================================
// MARK: - Key-Value Operations
// =============================================================================

RocksDBStatus rocksdb_put(RocksDBRef db, RocksDBWriteOptionsRef opts,
                          const char* key, size_t key_len,
                          const char* value, size_t value_len) {
  if (!db || !db->db) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Database is null");
    return result;
  }

  rocksdb::WriteOptions writeOpts;
  if (opts) {
    writeOpts = opts->options;
  }

  rocksdb::Status s = db->db->Put(
    writeOpts,
    rocksdb::Slice(key, key_len),
    rocksdb::Slice(value, value_len));

  return make_status(s);
}

RocksDBStatus rocksdb_get(RocksDBRef db, RocksDBReadOptionsRef opts,
                          const char* key, size_t key_len,
                          char** value_out, size_t* value_len_out) {
  *value_out = nullptr;
  *value_len_out = 0;

  if (!db || !db->db) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Database is null");
    return result;
  }

  rocksdb::ReadOptions readOpts;
  if (opts) {
    readOpts = opts->options;
  }

  std::string value;
  rocksdb::Status s = db->db->Get(
    readOpts,
    rocksdb::Slice(key, key_len),
    &value);

  if (s.ok()) {
    *value_len_out = value.size();
    *value_out = static_cast<char*>(malloc(value.size()));
    if (*value_out) {
      memcpy(*value_out, value.data(), value.size());
    }
  }

  return make_status(s);
}

RocksDBStatus rocksdb_delete(RocksDBRef db, RocksDBWriteOptionsRef opts,
                             const char* key, size_t key_len) {
  if (!db || !db->db) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Database is null");
    return result;
  }

  rocksdb::WriteOptions writeOpts;
  if (opts) {
    writeOpts = opts->options;
  }

  rocksdb::Status s = db->db->Delete(
    writeOpts,
    rocksdb::Slice(key, key_len));

  return make_status(s);
}

int rocksdb_key_may_exist(RocksDBRef db, RocksDBReadOptionsRef opts,
                          const char* key, size_t key_len) {
  if (!db || !db->db) {
    return 0;
  }

  rocksdb::ReadOptions readOpts;
  if (opts) {
    readOpts = opts->options;
  }

  std::string value;
  bool value_found = false;
  return db->db->KeyMayExist(readOpts, rocksdb::Slice(key, key_len), &value, &value_found) ? 1 : 0;
}

// =============================================================================
// MARK: - Batch Operations
// =============================================================================

RocksDBBatchRef rocksdb_batch_create(void) {
  return new RocksDBBatchHandle();
}

void rocksdb_batch_destroy(RocksDBBatchRef batch) {
  delete batch;
}

void rocksdb_batch_put(RocksDBBatchRef batch,
                       const char* key, size_t key_len,
                       const char* value, size_t value_len) {
  if (batch) {
    batch->batch.Put(rocksdb::Slice(key, key_len), rocksdb::Slice(value, value_len));
  }
}

void rocksdb_batch_delete(RocksDBBatchRef batch,
                          const char* key, size_t key_len) {
  if (batch) {
    batch->batch.Delete(rocksdb::Slice(key, key_len));
  }
}

void rocksdb_batch_delete_range(RocksDBBatchRef batch,
                                const char* start_key, size_t start_key_len,
                                const char* end_key, size_t end_key_len) {
  if (batch) {
    batch->batch.DeleteRange(rocksdb::Slice(start_key, start_key_len),
                             rocksdb::Slice(end_key, end_key_len));
  }
}

void rocksdb_batch_clear(RocksDBBatchRef batch) {
  if (batch) {
    batch->batch.Clear();
  }
}

size_t rocksdb_batch_count(RocksDBBatchRef batch) {
  return batch ? batch->batch.Count() : 0;
}

size_t rocksdb_batch_data_size(RocksDBBatchRef batch) {
  return batch ? batch->batch.GetDataSize() : 0;
}

RocksDBStatus rocksdb_write_batch(RocksDBRef db, RocksDBWriteOptionsRef opts,
                                  RocksDBBatchRef batch) {
  if (!db || !db->db || !batch) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Database or batch is null");
    return result;
  }

  rocksdb::WriteOptions writeOpts;
  if (opts) {
    writeOpts = opts->options;
  }

  rocksdb::Status s = db->db->Write(writeOpts, &batch->batch);
  return make_status(s);
}

// =============================================================================
// MARK: - Iterator Operations
// =============================================================================

RocksDBIteratorRef rocksdb_iterator_create(RocksDBRef db, RocksDBReadOptionsRef opts) {
  if (!db || !db->db) {
    return nullptr;
  }

  rocksdb::ReadOptions readOpts;
  if (opts) {
    readOpts = opts->options;
  }

  auto handle = new RocksDBIteratorHandle();
  handle->iter = db->db->NewIterator(readOpts);
  return handle;
}

void rocksdb_iterator_destroy(RocksDBIteratorRef iter) {
  delete iter;
}

int rocksdb_iterator_valid(RocksDBIteratorRef iter) {
  return (iter && iter->iter && iter->iter->Valid()) ? 1 : 0;
}

void rocksdb_iterator_seek_to_first(RocksDBIteratorRef iter) {
  if (iter && iter->iter) {
    iter->iter->SeekToFirst();
  }
}

void rocksdb_iterator_seek_to_last(RocksDBIteratorRef iter) {
  if (iter && iter->iter) {
    iter->iter->SeekToLast();
  }
}

void rocksdb_iterator_seek(RocksDBIteratorRef iter, const char* key, size_t key_len) {
  if (iter && iter->iter) {
    iter->iter->Seek(rocksdb::Slice(key, key_len));
  }
}

void rocksdb_iterator_seek_for_prev(RocksDBIteratorRef iter, const char* key, size_t key_len) {
  if (iter && iter->iter) {
    iter->iter->SeekForPrev(rocksdb::Slice(key, key_len));
  }
}

void rocksdb_iterator_next(RocksDBIteratorRef iter) {
  if (iter && iter->iter) {
    iter->iter->Next();
  }
}

void rocksdb_iterator_prev(RocksDBIteratorRef iter) {
  if (iter && iter->iter) {
    iter->iter->Prev();
  }
}

const char* rocksdb_iterator_key(RocksDBIteratorRef iter, size_t* len_out) {
  if (!iter || !iter->iter || !iter->iter->Valid()) {
    *len_out = 0;
    return nullptr;
  }

  rocksdb::Slice key = iter->iter->key();
  *len_out = key.size();
  return key.data();
}

const char* rocksdb_iterator_value(RocksDBIteratorRef iter, size_t* len_out) {
  if (!iter || !iter->iter || !iter->iter->Valid()) {
    *len_out = 0;
    return nullptr;
  }

  rocksdb::Slice value = iter->iter->value();
  *len_out = value.size();
  return value.data();
}

RocksDBStatus rocksdb_iterator_status(RocksDBIteratorRef iter) {
  if (!iter || !iter->iter) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Iterator is null");
    return result;
  }
  return make_status(iter->iter->status());
}

// =============================================================================
// MARK: - Transaction Operations
// =============================================================================

RocksDBTransactionRef rocksdb_transaction_begin(RocksDBRef db, RocksDBWriteOptionsRef opts) {
  if (!db || !db->is_transactional || !db->txn_db) {
    return nullptr;
  }

  rocksdb::WriteOptions writeOpts;
  if (opts) {
    writeOpts = opts->options;
  }

  auto handle = new RocksDBTransactionHandle();
  handle->txn = db->txn_db->BeginTransaction(writeOpts);
  return handle;
}

void rocksdb_transaction_destroy(RocksDBTransactionRef txn) {
  delete txn;
}

RocksDBStatus rocksdb_transaction_put(RocksDBTransactionRef txn,
                                      const char* key, size_t key_len,
                                      const char* value, size_t value_len) {
  if (!txn || !txn->txn) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Transaction is null");
    return result;
  }

  rocksdb::Status s = txn->txn->Put(rocksdb::Slice(key, key_len),
                                     rocksdb::Slice(value, value_len));
  return make_status(s);
}

RocksDBStatus rocksdb_transaction_get(RocksDBTransactionRef txn, RocksDBReadOptionsRef opts,
                                      const char* key, size_t key_len,
                                      char** value_out, size_t* value_len_out) {
  *value_out = nullptr;
  *value_len_out = 0;

  if (!txn || !txn->txn) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Transaction is null");
    return result;
  }

  rocksdb::ReadOptions readOpts;
  if (opts) {
    readOpts = opts->options;
  }

  std::string value;
  rocksdb::Status s = txn->txn->Get(readOpts, rocksdb::Slice(key, key_len), &value);

  if (s.ok()) {
    *value_len_out = value.size();
    *value_out = static_cast<char*>(malloc(value.size()));
    if (*value_out) {
      memcpy(*value_out, value.data(), value.size());
    }
  }

  return make_status(s);
}

RocksDBStatus rocksdb_transaction_get_for_update(RocksDBTransactionRef txn, RocksDBReadOptionsRef opts,
                                                  const char* key, size_t key_len,
                                                  char** value_out, size_t* value_len_out) {
  *value_out = nullptr;
  *value_len_out = 0;

  if (!txn || !txn->txn) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Transaction is null");
    return result;
  }

  rocksdb::ReadOptions readOpts;
  if (opts) {
    readOpts = opts->options;
  }

  std::string value;
  rocksdb::Status s = txn->txn->GetForUpdate(readOpts, rocksdb::Slice(key, key_len), &value);

  if (s.ok()) {
    *value_len_out = value.size();
    *value_out = static_cast<char*>(malloc(value.size()));
    if (*value_out) {
      memcpy(*value_out, value.data(), value.size());
    }
  }

  return make_status(s);
}

RocksDBStatus rocksdb_transaction_delete(RocksDBTransactionRef txn,
                                         const char* key, size_t key_len) {
  if (!txn || !txn->txn) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Transaction is null");
    return result;
  }

  rocksdb::Status s = txn->txn->Delete(rocksdb::Slice(key, key_len));
  return make_status(s);
}

RocksDBIteratorRef rocksdb_transaction_create_iterator(RocksDBTransactionRef txn,
                                                        RocksDBReadOptionsRef opts) {
  if (!txn || !txn->txn) {
    return nullptr;
  }

  rocksdb::ReadOptions readOpts;
  if (opts) {
    readOpts = opts->options;
  }

  auto handle = new RocksDBIteratorHandle();
  handle->iter = txn->txn->GetIterator(readOpts);
  return handle;
}

RocksDBStatus rocksdb_transaction_commit(RocksDBTransactionRef txn) {
  if (!txn || !txn->txn) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Transaction is null");
    return result;
  }

  rocksdb::Status s = txn->txn->Commit();
  return make_status(s);
}

void rocksdb_transaction_rollback(RocksDBTransactionRef txn) {
  if (txn && txn->txn) {
    txn->txn->Rollback();
  }
}

void rocksdb_transaction_set_savepoint(RocksDBTransactionRef txn) {
  if (txn && txn->txn) {
    txn->txn->SetSavePoint();
  }
}

RocksDBStatus rocksdb_transaction_rollback_to_savepoint(RocksDBTransactionRef txn) {
  if (!txn || !txn->txn) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Transaction is null");
    return result;
  }

  rocksdb::Status s = txn->txn->RollbackToSavePoint();
  return make_status(s);
}

// =============================================================================
// MARK: - Snapshot Operations
// =============================================================================

RocksDBSnapshotRef rocksdb_create_snapshot(RocksDBRef db) {
  if (!db || !db->db) {
    return nullptr;
  }

  auto handle = new RocksDBSnapshotHandle();
  handle->snapshot = db->db->GetSnapshot();
  return handle;
}

void rocksdb_release_snapshot(RocksDBRef db, RocksDBSnapshotRef snapshot) {
  if (db && db->db && snapshot && snapshot->snapshot) {
    db->db->ReleaseSnapshot(snapshot->snapshot);
  }
  delete snapshot;
}

// =============================================================================
// MARK: - Maintenance Operations
// =============================================================================

RocksDBStatus rocksdb_compact_range(RocksDBRef db,
                                    const char* start_key, size_t start_key_len,
                                    const char* end_key, size_t end_key_len) {
  if (!db || !db->db) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Database is null");
    return result;
  }

  rocksdb::CompactRangeOptions compactOpts;

  rocksdb::Slice* start = nullptr;
  rocksdb::Slice* end = nullptr;
  rocksdb::Slice startSlice, endSlice;

  if (start_key && start_key_len > 0) {
    startSlice = rocksdb::Slice(start_key, start_key_len);
    start = &startSlice;
  }
  if (end_key && end_key_len > 0) {
    endSlice = rocksdb::Slice(end_key, end_key_len);
    end = &endSlice;
  }

  rocksdb::Status s = db->db->CompactRange(compactOpts, start, end);
  return make_status(s);
}

RocksDBStatus rocksdb_flush(RocksDBRef db, int wait) {
  if (!db || !db->db) {
    RocksDBStatus result;
    result.code = RocksDBStatusInvalidArgument;
    result.message = strdup("Database is null");
    return result;
  }

  rocksdb::FlushOptions flushOpts;
  flushOpts.wait = (wait != 0);

  rocksdb::Status s = db->db->Flush(flushOpts);
  return make_status(s);
}

char* rocksdb_get_property(RocksDBRef db, const char* property) {
  if (!db || !db->db) {
    return nullptr;
  }

  std::string value;
  if (db->db->GetProperty(property, &value)) {
    return strdup(value.c_str());
  }
  return nullptr;
}

void rocksdb_get_approximate_sizes(RocksDBRef db,
                                   int num_ranges,
                                   const char* const* start_keys,
                                   const size_t* start_key_lens,
                                   const char* const* end_keys,
                                   const size_t* end_key_lens,
                                   uint64_t* sizes_out) {
  if (!db || !db->db || num_ranges <= 0) {
    return;
  }

  std::vector<rocksdb::Range> ranges;
  ranges.reserve(num_ranges);

  for (int i = 0; i < num_ranges; i++) {
    ranges.emplace_back(
      rocksdb::Slice(start_keys[i], start_key_lens[i]),
      rocksdb::Slice(end_keys[i], end_key_lens[i])
    );
  }

  db->db->GetApproximateSizes(ranges.data(), num_ranges, sizes_out);
}
