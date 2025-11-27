//
//  RocksDBBridge.h
//  RocksDB.swift
//
//  C bridge for RocksDB C++ API - enables Swift interoperability
//

#ifndef RocksDBBridge_h
#define RocksDBBridge_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// MARK: - Opaque Handle Types
// =============================================================================

typedef struct RocksDBHandle* RocksDBRef;
typedef struct RocksDBIteratorHandle* RocksDBIteratorRef;
typedef struct RocksDBBatchHandle* RocksDBBatchRef;
typedef struct RocksDBTransactionHandle* RocksDBTransactionRef;
typedef struct RocksDBOptionsHandle* RocksDBOptionsRef;
typedef struct RocksDBReadOptionsHandle* RocksDBReadOptionsRef;
typedef struct RocksDBWriteOptionsHandle* RocksDBWriteOptionsRef;
typedef struct RocksDBSnapshotHandle* RocksDBSnapshotRef;

// =============================================================================
// MARK: - Status Codes
// =============================================================================

typedef enum {
  RocksDBStatusOK = 0,
  RocksDBStatusNotFound = 1,
  RocksDBStatusCorruption = 2,
  RocksDBStatusNotSupported = 3,
  RocksDBStatusInvalidArgument = 4,
  RocksDBStatusIOError = 5,
  RocksDBStatusMergeInProgress = 6,
  RocksDBStatusIncomplete = 7,
  RocksDBStatusShutdownInProgress = 8,
  RocksDBStatusTimedOut = 9,
  RocksDBStatusAborted = 10,
  RocksDBStatusBusy = 11,
  RocksDBStatusExpired = 12,
  RocksDBStatusTryAgain = 13,
  RocksDBStatusCompactionTooLarge = 14
} RocksDBStatusCode;

typedef struct {
  RocksDBStatusCode code;
  char* message;  // Caller must free with rocksdb_free_string
} RocksDBStatus;

// =============================================================================
// MARK: - Compression Types
// =============================================================================

typedef enum {
  RocksDBCompressionNone = 0,
  RocksDBCompressionSnappy = 1,
  RocksDBCompressionZlib = 2,
  RocksDBCompressionBZ2 = 3,
  RocksDBCompressionLZ4 = 4,
  RocksDBCompressionLZ4HC = 5,
  RocksDBCompressionXpress = 6,
  RocksDBCompressionZSTD = 7
} RocksDBCompressionType;

// =============================================================================
// MARK: - Memory Management
// =============================================================================

void rocksdb_free_string(char* str);
void rocksdb_free_data(void* data);

// =============================================================================
// MARK: - Options
// =============================================================================

// Database Options
RocksDBOptionsRef rocksdb_options_create(void);
void rocksdb_options_destroy(RocksDBOptionsRef opts);
void rocksdb_options_set_create_if_missing(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_error_if_exists(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_paranoid_checks(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_compression(RocksDBOptionsRef opts, int type);
void rocksdb_options_set_write_buffer_size(RocksDBOptionsRef opts, size_t size);
void rocksdb_options_set_max_write_buffer_number(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_max_open_files(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_max_background_compactions(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_max_background_flushes(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_level0_file_num_compaction_trigger(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_level0_slowdown_writes_trigger(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_level0_stop_writes_trigger(RocksDBOptionsRef opts, int value);
void rocksdb_options_set_target_file_size_base(RocksDBOptionsRef opts, uint64_t size);
void rocksdb_options_set_max_bytes_for_level_base(RocksDBOptionsRef opts, uint64_t size);
void rocksdb_options_enable_statistics(RocksDBOptionsRef opts);
void rocksdb_options_optimize_for_point_lookup(RocksDBOptionsRef opts, uint64_t block_cache_size_mb);
void rocksdb_options_optimize_level_style_compaction(RocksDBOptionsRef opts, uint64_t memtable_memory_budget);

// Read Options
RocksDBReadOptionsRef rocksdb_read_options_create(void);
void rocksdb_read_options_destroy(RocksDBReadOptionsRef opts);
void rocksdb_read_options_set_verify_checksums(RocksDBReadOptionsRef opts, int value);
void rocksdb_read_options_set_fill_cache(RocksDBReadOptionsRef opts, int value);
void rocksdb_read_options_set_snapshot(RocksDBReadOptionsRef opts, RocksDBSnapshotRef snapshot);
void rocksdb_read_options_set_prefix_same_as_start(RocksDBReadOptionsRef opts, int value);

// Write Options
RocksDBWriteOptionsRef rocksdb_write_options_create(void);
void rocksdb_write_options_destroy(RocksDBWriteOptionsRef opts);
void rocksdb_write_options_set_sync(RocksDBWriteOptionsRef opts, int value);
void rocksdb_write_options_disable_wal(RocksDBWriteOptionsRef opts, int value);

// =============================================================================
// MARK: - Database Operations
// =============================================================================

RocksDBStatus rocksdb_open(const char* path, RocksDBOptionsRef opts, RocksDBRef* db_out);
RocksDBStatus rocksdb_open_for_read_only(const char* path, RocksDBOptionsRef opts,
                                          int error_if_wal_exists, RocksDBRef* db_out);
RocksDBStatus rocksdb_open_transactional(const char* path, RocksDBOptionsRef opts, RocksDBRef* db_out);
void rocksdb_close(RocksDBRef db);

// Check if database was opened with transaction support
int rocksdb_is_transactional(RocksDBRef db);

// =============================================================================
// MARK: - Key-Value Operations
// =============================================================================

RocksDBStatus rocksdb_put(RocksDBRef db, RocksDBWriteOptionsRef opts,
                          const char* key, size_t key_len,
                          const char* value, size_t value_len);

RocksDBStatus rocksdb_get(RocksDBRef db, RocksDBReadOptionsRef opts,
                          const char* key, size_t key_len,
                          char** value_out, size_t* value_len_out);

RocksDBStatus rocksdb_delete(RocksDBRef db, RocksDBWriteOptionsRef opts,
                             const char* key, size_t key_len);

int rocksdb_key_may_exist(RocksDBRef db, RocksDBReadOptionsRef opts,
                          const char* key, size_t key_len);

// =============================================================================
// MARK: - Batch Operations
// =============================================================================

RocksDBBatchRef rocksdb_batch_create(void);
void rocksdb_batch_destroy(RocksDBBatchRef batch);

void rocksdb_batch_put(RocksDBBatchRef batch,
                       const char* key, size_t key_len,
                       const char* value, size_t value_len);

void rocksdb_batch_delete(RocksDBBatchRef batch,
                          const char* key, size_t key_len);

void rocksdb_batch_delete_range(RocksDBBatchRef batch,
                                const char* start_key, size_t start_key_len,
                                const char* end_key, size_t end_key_len);

void rocksdb_batch_clear(RocksDBBatchRef batch);
size_t rocksdb_batch_count(RocksDBBatchRef batch);
size_t rocksdb_batch_data_size(RocksDBBatchRef batch);

RocksDBStatus rocksdb_write_batch(RocksDBRef db, RocksDBWriteOptionsRef opts,
                                  RocksDBBatchRef batch);

// =============================================================================
// MARK: - Iterator Operations
// =============================================================================

RocksDBIteratorRef rocksdb_iterator_create(RocksDBRef db, RocksDBReadOptionsRef opts);
void rocksdb_iterator_destroy(RocksDBIteratorRef iter);

int rocksdb_iterator_valid(RocksDBIteratorRef iter);
void rocksdb_iterator_seek_to_first(RocksDBIteratorRef iter);
void rocksdb_iterator_seek_to_last(RocksDBIteratorRef iter);
void rocksdb_iterator_seek(RocksDBIteratorRef iter, const char* key, size_t key_len);
void rocksdb_iterator_seek_for_prev(RocksDBIteratorRef iter, const char* key, size_t key_len);
void rocksdb_iterator_next(RocksDBIteratorRef iter);
void rocksdb_iterator_prev(RocksDBIteratorRef iter);

// Returns pointer to internal data - do NOT free, valid until next iterator operation
const char* rocksdb_iterator_key(RocksDBIteratorRef iter, size_t* len_out);
const char* rocksdb_iterator_value(RocksDBIteratorRef iter, size_t* len_out);

RocksDBStatus rocksdb_iterator_status(RocksDBIteratorRef iter);

// =============================================================================
// MARK: - Transaction Operations (OptimisticTransactionDB)
// =============================================================================

RocksDBTransactionRef rocksdb_transaction_begin(RocksDBRef db, RocksDBWriteOptionsRef opts);
void rocksdb_transaction_destroy(RocksDBTransactionRef txn);

RocksDBStatus rocksdb_transaction_put(RocksDBTransactionRef txn,
                                      const char* key, size_t key_len,
                                      const char* value, size_t value_len);

RocksDBStatus rocksdb_transaction_get(RocksDBTransactionRef txn, RocksDBReadOptionsRef opts,
                                      const char* key, size_t key_len,
                                      char** value_out, size_t* value_len_out);

RocksDBStatus rocksdb_transaction_get_for_update(RocksDBTransactionRef txn, RocksDBReadOptionsRef opts,
                                                  const char* key, size_t key_len,
                                                  char** value_out, size_t* value_len_out);

RocksDBStatus rocksdb_transaction_delete(RocksDBTransactionRef txn,
                                         const char* key, size_t key_len);

RocksDBIteratorRef rocksdb_transaction_create_iterator(RocksDBTransactionRef txn,
                                                        RocksDBReadOptionsRef opts);

RocksDBStatus rocksdb_transaction_commit(RocksDBTransactionRef txn);
void rocksdb_transaction_rollback(RocksDBTransactionRef txn);

void rocksdb_transaction_set_savepoint(RocksDBTransactionRef txn);
RocksDBStatus rocksdb_transaction_rollback_to_savepoint(RocksDBTransactionRef txn);

// =============================================================================
// MARK: - Snapshot Operations
// =============================================================================

RocksDBSnapshotRef rocksdb_create_snapshot(RocksDBRef db);
void rocksdb_release_snapshot(RocksDBRef db, RocksDBSnapshotRef snapshot);

// =============================================================================
// MARK: - Maintenance Operations
// =============================================================================

RocksDBStatus rocksdb_compact_range(RocksDBRef db,
                                    const char* start_key, size_t start_key_len,
                                    const char* end_key, size_t end_key_len);

RocksDBStatus rocksdb_flush(RocksDBRef db, int wait);

// Returns newly allocated string, caller must free with rocksdb_free_string
char* rocksdb_get_property(RocksDBRef db, const char* property);

// Approximate sizes
void rocksdb_get_approximate_sizes(RocksDBRef db,
                                   int num_ranges,
                                   const char* const* start_keys,
                                   const size_t* start_key_lens,
                                   const char* const* end_keys,
                                   const size_t* end_key_lens,
                                   uint64_t* sizes_out);

#ifdef __cplusplus
}
#endif

#endif /* RocksDBBridge_h */
