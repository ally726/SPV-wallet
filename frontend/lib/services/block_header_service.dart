import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/block_header.dart';
import '../database/database_helper.dart';
import '../utils/constants.dart';
import 'api_services.dart';

/// Block Header synchronization service
/// Downloads and stores block headers from trusted backend
class BlockHeaderService {
  static final BlockHeaderService instance = BlockHeaderService._internal();

  final ApiService _api = ApiService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Sync status
  bool _isSyncing = false;
  int _currentHeight = 0;

  // Sync progress callback
  Function(int currentHeight, int targetHeight)? onSyncProgress;

  BlockHeaderService._internal();

  // ==================== Initialization ====================

  /// Initialize service and load current sync state
  Future<void> initialize() async {
    try {
      _currentHeight = await _db.getLastSyncedHeight();
      debugPrint('[BlockHeader] Initialized at height: $_currentHeight');
    } catch (e) {
      debugPrint('[BlockHeader] Failed to initialize: $e');
      _currentHeight = 0;
    }
  }

  /// Get current synced height
  int get currentHeight => _currentHeight;

  /// Check if currently syncing
  bool get isSyncing => _isSyncing;

  // ==================== Block Header Synchronization ====================

  /// Start syncing block headers from current height
  Future<void> startSync({int? targetHeight}) async {
    if (_isSyncing) {
      throw BlockHeaderException('Sync already in progress');
    }

    _isSyncing = true;

    try {
      debugPrint('[BlockHeader] Starting sync from height $_currentHeight');

      // Get starting hash from database, or let backend provide genesis if height is 0
      String? startHash;
      if (_currentHeight > 0) {
        final currentTip = await _db.getBlockHeaderByHeight(_currentHeight);
        if (currentTip == null) {
          throw BlockHeaderException(
              'Cannot find block at height $_currentHeight');
        }
        startHash = currentTip.hash;
      }

      // Sync in batches
      bool hasMore = true;
      while (hasMore && _isSyncing) {
        final headers = await _api.getHeaders(
          startHash: startHash ?? '',
          count: AppConstants.blockHeadersPerBatch,
        );

        if (headers.isEmpty) {
          hasMore = false;
          break;
        }

        debugPrint(
            '[BlockHeader] Received ${headers.length} headers starting from height ${headers.first.height}');

        // Store headers directly (backend already validated)
        await _processHeaders(headers);

        // Update progress
        _currentHeight = headers.last.height;
        await _db.setLastSyncedHeight(_currentHeight);

        // Progress callback
        if (onSyncProgress != null && targetHeight != null) {
          onSyncProgress!(_currentHeight, targetHeight);
        }

        // Check if reached target or chain tip
        if (targetHeight != null && _currentHeight >= targetHeight) {
          hasMore = false;
          break;
        }

        if (headers.length < AppConstants.blockHeadersPerBatch) {
          hasMore = false;
          break;
        }

        startHash = headers.last.hash;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      debugPrint('[BlockHeader] Sync completed at height $_currentHeight');
    } catch (e) {
      debugPrint('[BlockHeader] Sync error: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// Stop ongoing sync
  void stopSync() {
    _isSyncing = false;
    debugPrint('[BlockHeader] Sync stopped at height $_currentHeight');
  }

  // ==================== Header Processing ====================

  /// Store headers in database (no validation - backend is trusted)
  Future<void> _processHeaders(List<BlockHeader> headers) async {
    if (headers.isEmpty) return;
    await _db.insertBlockHeaders(headers);
  }

  // ==================== Query Methods ====================

  /// Get block header by height
  Future<BlockHeader?> getBlockHeaderByHeight(int height) async {
    return await _db.getBlockHeaderByHeight(height);
  }

  /// Get confirmations for a block at given height
  int getConfirmations(int blockHeight) {
    if (blockHeight > _currentHeight) return 0;
    return _currentHeight - blockHeight + 1;
  }

  // ==================== Utility Methods ====================

  /// Get sync statistics (simplified)
  Future<SyncStatistics> getSyncStatistics() async {
    return SyncStatistics(
      currentHeight: _currentHeight,
      isSyncing: _isSyncing,
    );
  }
}

/// Simplified sync statistics
class SyncStatistics {
  final int currentHeight;
  final bool isSyncing;

  SyncStatistics({
    required this.currentHeight,
    required this.isSyncing,
  });

  @override
  String toString() {
    return 'SyncStatistics(height: $currentHeight, syncing: $isSyncing)';
  }
}

/// Custom exception for block header operations
class BlockHeaderException implements Exception {
  final String message;

  BlockHeaderException(this.message);

  @override
  String toString() => 'BlockHeaderException: $message';
}
