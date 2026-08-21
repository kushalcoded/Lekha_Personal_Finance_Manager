import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/responsive/responsive_sheet.dart';
import '../../expenses/providers/expenses_providers.dart';
import '../providers/productivity_providers.dart';
import '../providers/settings_providers.dart';
import '../../../utils/formatters/formatters.dart';

Future<void> showExportModal(BuildContext context) {
  return showResponsiveSheet(
    context,
    maxWidth: 620,
    mobileChild: const ExportModalContent(),
    desktopChild: const ExportModalContent(isDialog: true),
  );
}

class ExportModalContent extends ConsumerStatefulWidget {
  final bool isDialog;

  const ExportModalContent({super.key, this.isDialog = false});

  @override
  ConsumerState<ExportModalContent> createState() => _ExportModalContentState();
}

class _ExportModalContentState extends ConsumerState<ExportModalContent> {
  DateTimeRange? _dateRange;
  final Set<String> _categories = {};
  ExportFormat _format = ExportFormat.csv;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _format = _parseFormat(settings.defaultExportFormat);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final exportState = ref.watch(exportProvider);
    final categories = ref.watch(expenseCategoriesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, widget.isDialog ? 20 : 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isDialog)
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Export Data',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ExportFormat>(
            key: ValueKey('export-format-${_format.name}'),
            initialValue: _format,
            decoration: const InputDecoration(labelText: 'Format'),
            items: ExportFormat.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value.name.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _format = value);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date range'),
            subtitle: Text(
              _dateRange == null
                  ? 'All dates'
                  : '${AppFormatters.formatDate(_dateRange!.start)} - '
                        '${AppFormatters.formatDate(_dateRange!.end)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Text('Categories', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((category) {
              final selected = _categories.contains(category);
              return FilterChip(
                label: Text(category),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    if (selected) {
                      _categories.remove(category);
                    } else {
                      _categories.add(category);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include analytics summary'),
            value: settings.exportIncludeAnalyticsSummary,
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .setExportIncludeAnalyticsSummary(value),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: exportState.isRunning ? null : _runExport,
            child: Text(
              exportState.isRunning ? 'Exporting...' : 'Generate Export',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            exportState.status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (exportState.isRunning)
            LinearProgressIndicator(value: exportState.progress),
          if (!exportState.isRunning && exportState.lastFile != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.read(exportProvider.notifier).shareLastExport(),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
          if (exportState.error != null) ...[
            const SizedBox(height: 8),
            Text(
              exportState.error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],
          if (exportState.preview != null) ...[
            const SizedBox(height: 12),
            Text(
              'Preview',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                exportState.preview!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (exportState.history.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Recent exports',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...exportState.history
                .take(4)
                .map(
                  (item) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.25,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${AppFormatters.formatDateTime(item.createdAt)}'
                          ' · ${item.format.toUpperCase()}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if ((item.savedPath ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.savedPath!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _runExport() async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(exportProvider.notifier)
        .runExport(
          ExportRequest(
            dateRange: _dateRange,
            categories: _categories.toList(),
            includeAnalyticsSummary: settings.exportIncludeAnalyticsSummary,
            format: _format,
            darkTheme: Theme.of(context).brightness == Brightness.dark,
          ),
        );
    if (!mounted) return;
    await ref
        .read(settingsProvider.notifier)
        .setDefaultExportFormat(_format.name);
  }

  ExportFormat _parseFormat(String value) {
    return ExportFormat.values.firstWhere(
      (format) => format.name == value,
      orElse: () => ExportFormat.csv,
    );
  }
}
