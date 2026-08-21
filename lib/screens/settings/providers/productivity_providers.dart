import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/expense/expense_model.dart';
import '../../../models/receivable/receivable_model.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../services/storage/hive_service.dart';
import '../../../services/backup/backup_file_service.dart';
import '../../../services/export/export_file_service.dart';
import '../../../services/export/export_models.dart';
import '../../../services/export/export_service.dart';

enum ExportFormat { csv, pdf, excel }

class ExportRequest {
  final DateTimeRange? dateRange;
  final List<String> categories;
  final bool includeAnalyticsSummary;
  final ExportFormat format;
  final bool darkTheme;

  const ExportRequest({
    this.dateRange,
    this.categories = const [],
    required this.includeAnalyticsSummary,
    required this.format,
    required this.darkTheme,
  });
}

class ExportState {
  final bool isRunning;
  final double progress;
  final String status;
  final String? preview;
  final String? error;
  final ExportSavedFile? lastFile;
  final List<ExportHistoryItem> history;

  const ExportState({
    this.isRunning = false,
    this.progress = 0,
    this.status = 'Idle',
    this.preview,
    this.error,
    this.lastFile,
    this.history = const [],
  });

  ExportState copyWith({
    bool? isRunning,
    double? progress,
    String? status,
    String? preview,
    String? error,
    ExportSavedFile? lastFile,
    List<ExportHistoryItem>? history,
  }) {
    return ExportState(
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      preview: preview ?? this.preview,
      error: error ?? this.error,
      lastFile: lastFile ?? this.lastFile,
      history: history ?? this.history,
    );
  }
}

class ExportHistoryItem {
  final String fileName;
  final String format;
  final DateTime createdAt;
  final String? savedPath;

  const ExportHistoryItem({
    required this.fileName,
    required this.format,
    required this.createdAt,
    required this.savedPath,
  });

  static ExportHistoryItem fromMap(Map<String, dynamic> map) {
    return ExportHistoryItem(
      fileName: map['fileName'] as String? ?? 'export',
      format: map['format'] as String? ?? 'unknown',
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      savedPath: map['savedPath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'format': format,
      'createdAt': createdAt.toIso8601String(),
      'savedPath': savedPath,
    };
  }
}

class ExportNotifier extends StateNotifier<ExportState> {
  final Ref _ref;
  final ExportService _exportService;
  final ExportFileService _fileService;

  ExportNotifier(this._ref)
    : _exportService = const ExportService(),
      _fileService = const ExportFileService(),
      super(const ExportState()) {
    _loadHistory();
  }

  void _loadHistory() {
    try {
      final userId = _ref.read(currentUserIdProvider) ?? '';
      final hive = _ref.read(hiveServiceProvider);
      final raw = hive.getExportHistory(userId);
      final items = raw.map(ExportHistoryItem.fromMap).toList();
      state = state.copyWith(history: items);
    } catch (_) {}
  }

  Future<void> runExport(ExportRequest request) async {
    state = state.copyWith(
      isRunning: true,
      progress: 0.1,
      status: 'Collecting data',
      error: null,
    );
    try {
      final userId = _ref.read(currentUserIdProvider) ?? '';
      final hive = _ref.read(hiveServiceProvider);

      final expensesSource = _ref.read(expensesProvider).expenses;
      final expenses = _applyExpenseFilter(expensesSource, request);
      final receivables = _applyReceivableFilter(
        hive.getAllReceivables(userId),
        request,
      );
      final payables = hive.getAllPayables(userId);
      final recurring = hive.getRecurringTemplates(userId);
      final budget = hive.getMonthlyBudget(userId, DateTime.now());
      final currentMonthSpent = _sumCurrentMonth(
        expensesSource,
        userId: userId,
      );

      state = state.copyWith(progress: 0.38, status: 'Generating export');

      final fileNameBase =
          'lekha_export_${DateTime.now().millisecondsSinceEpoch}';
      final dataset = ExportDataset(
        expenses: expenses,
        receivables: receivables,
        payables: payables,
        recurringTemplates: recurring,
        budget: ExportBudgetSnapshot(budget: budget, spent: currentMonthSpent),
      );

      final generated = switch (request.format) {
        ExportFormat.csv => _exportService.generateCsv(
          dataset: dataset,
          includeAnalyticsSummary: request.includeAnalyticsSummary,
          darkTheme: request.darkTheme,
          fileNameBase: fileNameBase,
        ),
        ExportFormat.excel => _exportService.generateExcel(
          dataset: dataset,
          includeAnalyticsSummary: request.includeAnalyticsSummary,
          darkTheme: request.darkTheme,
          fileNameBase: fileNameBase,
        ),
        ExportFormat.pdf => await _exportService.generatePdf(
          dataset: dataset,
          includeAnalyticsSummary: request.includeAnalyticsSummary,
          darkTheme: request.darkTheme,
          title: 'Lekha Report',
          fileNameBase: fileNameBase,
        ),
      };

      state = state.copyWith(progress: 0.72, status: 'Saving file');
      final saved = await _fileService.persistGeneratedFile(generated);
      await hive.addExportHistoryEntry(
        userId,
        ExportHistoryItem(
          fileName: saved.fileName,
          format: request.format.name,
          createdAt: DateTime.now(),
          savedPath: saved.savedPath,
        ).toMap(),
      );

      state = state.copyWith(
        isRunning: false,
        progress: 1.0,
        status: saved.hasUserChosenLocation
            ? 'Saved to ${saved.savedPath}'
            : 'Export ready (temp file)',
        preview: generated.previewText,
        lastFile: saved,
        history: [
          ExportHistoryItem(
            fileName: saved.fileName,
            format: request.format.name,
            createdAt: DateTime.now(),
            savedPath: saved.savedPath,
          ),
          ...state.history,
        ].take(12).toList(),
      );
    } catch (e) {
      state = state.copyWith(
        isRunning: false,
        progress: 0,
        status: 'Export failed',
        error: e.toString(),
      );
    }
  }

  Future<void> shareLastExport() async {
    final file = state.lastFile;
    if (file == null) return;
    // Web exports carry bytes instead of a temp path.
    final xFile = file.tempPath.isEmpty && file.bytes != null
        ? XFile.fromData(
            file.bytes!,
            mimeType: file.mimeType,
            name: file.fileName,
          )
        : XFile(file.tempPath, mimeType: file.mimeType, name: file.fileName);
    try {
      await SharePlus.instance.share(
        ShareParams(files: [xFile], text: 'Lekha export: ${file.fileName}'),
      );
    } catch (e) {
      // Surfaced through the same state the rest of this notifier uses, which
      // Settings already renders. Without it a failing share sheet was a tap
      // that did nothing at all.
      state = state.copyWith(error: 'Could not share the export: $e');
    }
  }

  List<Expense> _applyExpenseFilter(
    List<Expense> input,
    ExportRequest request,
  ) {
    var result = List<Expense>.from(input);
    if (request.dateRange != null) {
      final start = DateTime(
        request.dateRange!.start.year,
        request.dateRange!.start.month,
        request.dateRange!.start.day,
      );
      final end = DateTime(
        request.dateRange!.end.year,
        request.dateRange!.end.month,
        request.dateRange!.end.day,
        23,
        59,
        59,
        999,
      );
      result = result
          .where(
            (expense) =>
                !expense.date.isBefore(start) && !expense.date.isAfter(end),
          )
          .toList();
    }
    if (request.categories.isNotEmpty) {
      result = result
          .where((expense) => request.categories.contains(expense.category))
          .toList();
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  List<Receivable> _applyReceivableFilter(
    List<Receivable> input,
    ExportRequest request,
  ) {
    if (request.dateRange == null) return input;
    final start = DateTime(
      request.dateRange!.start.year,
      request.dateRange!.start.month,
      request.dateRange!.start.day,
    );
    final end = DateTime(
      request.dateRange!.end.year,
      request.dateRange!.end.month,
      request.dateRange!.end.day,
      23,
      59,
      59,
      999,
    );
    return input
        .where((r) => !r.dueDate.isBefore(start) && !r.dueDate.isAfter(end))
        .toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
  }

  double _sumCurrentMonth(List<Expense> expenses, {required String userId}) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return expenses
        .where(
          (e) =>
              e.userId == userId &&
              !e.date.isBefore(start) &&
              e.date.isBefore(end),
        )
        .fold(0.0, (s, e) => s + e.amount);
  }
}

final exportProvider = StateNotifierProvider<ExportNotifier, ExportState>(
  (ref) => ExportNotifier(ref),
);

class BackupMetadata {
  final String backupId;
  final DateTime createdAt;
  final int expenseCount;
  final int receivableCount;
  final int payableCount;
  final int recurringTemplateCount;

  const BackupMetadata({
    required this.backupId,
    required this.createdAt,
    required this.expenseCount,
    required this.receivableCount,
    required this.payableCount,
    required this.recurringTemplateCount,
  });
}

class BackupState {
  final bool isLoading;
  final String? error;
  final List<BackupMetadata> backups;

  const BackupState({
    this.isLoading = false,
    this.error,
    this.backups = const [],
  });

  BackupState copyWith({
    bool? isLoading,
    String? error,
    List<BackupMetadata>? backups,
  }) {
    return BackupState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      backups: backups ?? this.backups,
    );
  }
}

class BackupNotifier extends StateNotifier<BackupState> {
  final HiveService _hiveService;
  final BackupFileService _backupFileService;
  final String _userId;

  BackupNotifier(this._hiveService, this._userId)
    : _backupFileService = const BackupFileService(),
      super(const BackupState()) {
    loadBackups();
  }

  Future<void> loadBackups() async {
    try {
      final raw = _hiveService.getLocalBackups();
      final backups = raw.map(_metadataFromMap).toList();
      state = state.copyWith(backups: backups, isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> createBackup() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final snapshot = _hiveService.createLocalBackupSnapshot(_userId);
      await _hiveService.saveLocalBackup(snapshot);
      final backups = _hiveService
          .getLocalBackups()
          .map(_metadataFromMap)
          .toList();
      state = state.copyWith(isLoading: false, backups: backups);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> restoreLocalBackup(String backupId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final snapshot = _hiveService.getLocalBackupById(backupId);
      if (snapshot == null) {
        throw Exception('Backup not found: $backupId');
      }
      await _hiveService.restoreFromBackup(snapshot);
      await loadBackups();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Write the full dataset to a `.json` file and open the share sheet, so the
  /// user can save it off-device (Drive, email…) and restore it later via
  /// Import — the real safety net that survives an uninstall.
  Future<void> exportBackupFile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final snapshot = _hiveService.createLocalBackupSnapshot(_userId);
      final XFile file;
      if (kIsWeb) {
        // No filesystem on web — share the bytes directly.
        file = XFile.fromData(
          _backupFileService.backupBytes(snapshot),
          mimeType: 'application/json',
          name: _backupFileService.backupFileName(),
        );
      } else {
        final path = await _backupFileService.writeBackupFile(snapshot);
        file = XFile(
          path,
          mimeType: 'application/json',
          name: path.split('/').last,
        );
      }
      await SharePlus.instance.share(
        ShareParams(files: [file], text: 'Lekha backup'),
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> importBackupFromFile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final path = await _backupFileService.pickBackupFile();
      if (path == null) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final snapshot = await _backupFileService.readBackupPayload(path);
      await _hiveService.restoreFromBackup(snapshot);
      await loadBackups();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  BackupMetadata _metadataFromMap(Map<String, dynamic> input) {
    final expenses = input['expenses'] as List<dynamic>? ?? [];
    final receivables = input['receivables'] as List<dynamic>? ?? [];
    final payables = input['payables'] as List<dynamic>? ?? [];
    final recurring = input['recurringTemplates'] as List<dynamic>? ?? [];
    return BackupMetadata(
      backupId: input['backupId'] as String? ?? 'unknown',
      createdAt:
          DateTime.tryParse(input['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expenseCount: expenses.length,
      receivableCount: receivables.length,
      payableCount: payables.length,
      recurringTemplateCount: recurring.length,
    );
  }
}

final backupProvider = StateNotifierProvider<BackupNotifier, BackupState>((
  ref,
) {
  final hiveService = ref.watch(hiveServiceProvider);
  final userId = ref.watch(currentUserIdProvider) ?? '';
  return BackupNotifier(hiveService, userId);
});
