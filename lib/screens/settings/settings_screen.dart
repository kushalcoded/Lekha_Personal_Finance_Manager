import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../navigation/floating_glass_nav.dart' show kWideBreakpoint;
import '../../providers/ai_providers.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/budget/category_budget_providers.dart';
import '../../providers/sms/sms_providers.dart';
import '../../providers/sync/sync_providers.dart';
import '../../providers/update_providers.dart';
import '../ai_chat_screen.dart';
import 'providers/productivity_providers.dart';
import 'providers/settings_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/common/update_flow.dart';
import '../../utils/web_reload/web_reload_stub.dart'
    if (dart.library.js_interop) '../../utils/web_reload/web_reload_web.dart';
import '../cycle_recap_dialog.dart';
import '../dashboard/widgets/budget_settings_modal.dart';
import 'widgets/export_modal.dart';
import 'widgets/iphone_sms_guide_screen.dart';
import 'widgets/manage_categories_screen.dart';
import 'widgets/manage_category_budgets_screen.dart';
import 'widgets/manage_payment_methods_screen.dart';
import 'widgets/manage_people_screen.dart';
import '../../providers/payment/payment_method_providers.dart';

/// Latest Android APK lives on the GitHub release page.
const _androidAppUrl =
    'https://github.com/kushalcoded/Lekha_Personal_Finance_Manager/releases/latest';

/// Settings screen — grouped, compact rows (icon · label · value/chevron/toggle)
/// over frosted cards, matching the Calm Ledger mockup.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final backups = ref.watch(backupProvider);
    final backupNotifier = ref.read(backupProvider.notifier);
    final currencies = ref.watch(currenciesProvider);
    final exportFormats = ref.watch(exportFormatsProvider);
    final export = ref.watch(exportProvider);
    final aiConfigured = ref.watch(geminiConfiguredProvider);

    ref.listen(backupProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (previous?.isLoading == true &&
          next.isLoading == false &&
          next.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup operation completed')),
        );
      }
    });

    ref.listen(exportProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (previous?.isRunning == true &&
          next.isRunning == false &&
          next.error == null &&
          next.lastFile != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export generated: ${next.lastFile!.fileName}'),
          ),
        );
      }
    });

    final remindersOn = settings.remindersEnabled;
    final appVersion = ref.watch(appVersionProvider).valueOrNull;
    final updateCheck = ref.watch(updateAvailableProvider);
    final updateVersion = updateCheck.valueOrNull;
    final updateCheckFailed = updateCheck.hasError;

    // Desktop: settings groups pair up two per row inside a capped column,
    // equalized via IntrinsicHeight (safe: no LayoutBuilder in the rows).
    final isWide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    Widget twoUp(Widget a, Widget b) => isWide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: a),
                const SizedBox(width: 14),
                Expanded(child: b),
              ],
            ),
          )
        : Column(children: [a, b]);

    final sync = ref.watch(syncProvider);
    final syncStatus = sync.isSyncing
        ? 'Syncing…'
        : sync.error != null
        ? 'Last sync failed — tap Sync now to retry'
        : sync.lastSyncedAt != null
        ? 'Last synced ${_formatCycleDate(sync.lastSyncedAt!)}'
        : 'Not synced yet';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Settings'), elevation: 0),
      body: settings.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await settingsNotifier.loadSettings();
                await backupNotifier.loadBackups();
              },
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      twoUp(
                        _SettingsGroup(
                          stretch: isWide,
                          label: 'Account',
                          rows: [
                            _SettingRow(
                              icon: Icons.person_rounded,
                              title: 'Signed in',
                              subtitle: ref.watch(currentUserEmailProvider),
                              trailing: _PillButton(
                                label: 'Sign out',
                                onTap: () => ref
                                    .read(authStateProvider.notifier)
                                    .logout(),
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.badge_rounded,
                              title: 'Display name',
                              value: settings.displayName.isEmpty
                                  ? 'Not set'
                                  : settings.displayName,
                              onTap: () => _editDisplayName(context, ref),
                            ),
                            _SettingRow(
                              icon: Icons.cloud_sync_rounded,
                              title: 'Sync',
                              subtitle: syncStatus,
                              trailing: sync.isSyncing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : _PillButton(
                                      label: 'Sync now',
                                      onTap: () => ref
                                          .read(syncProvider.notifier)
                                          .syncNow(),
                                    ),
                            ),
                          ],
                        ),
                        _SettingsGroup(
                          stretch: isWide,
                          label: 'Salary cycle',
                          rows: [
                            _SettingRow(
                              icon: Icons.flag_rounded,
                              title: 'Cycle budget',
                              value: settings.currentCycleBudget > 0
                                  ? AppFormatters.formatCurrency(
                                      settings.currentCycleBudget,
                                    )
                                  : 'Not set',
                              onTap: () => showBudgetSettingsModal(context),
                            ),
                            _SettingRow(
                              icon: Icons.account_balance_wallet_rounded,
                              title: 'Cycle salary',
                              value: settings.currentCycleSalary > 0
                                  ? AppFormatters.formatCurrency(
                                      settings.currentCycleSalary,
                                    )
                                  : 'Not set',
                              onTap: () => showSalarySettingsModal(context),
                            ),
                            _SettingRow(
                              icon: Icons.event_repeat_rounded,
                              title: 'Salary day',
                              subtitle: settings.salaryDay == null
                                  ? 'Get asked to start a new cycle'
                                  : 'Asks around the '
                                        '${_ordinal(settings.salaryDay!)} — '
                                        'you confirm the real date',
                              value: settings.salaryDay == null
                                  ? 'Not set'
                                  : _ordinal(settings.salaryDay!),
                              onTap: () => _pickSalaryDay(context, ref),
                            ),
                            _SettingRow(
                              icon: Icons.restart_alt_rounded,
                              title: 'Current cycle',
                              subtitle:
                                  'Started ${_formatCycleDate(settings.currentCycleStartDate)}',
                              trailing: _PillButton(
                                label: 'Reset',
                                onTap: () => _confirmReset(context, ref),
                              ),
                            ),
                          ],
                        ),
                      ),
                      twoUp(
                        _SettingsGroup(
                          stretch: isWide,
                          label: 'Preferences',
                          rows: [
                            _SettingRow(
                              icon: Icons.payments_outlined,
                              title: 'Currency',
                              value: settings.currency,
                              onTap: () => _pickOption(
                                context,
                                title: 'Default currency',
                                options: currencies,
                                current: settings.currency,
                                onSelected: settingsNotifier.setCurrency,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.file_download_outlined,
                              title: 'Default export',
                              value: settings.defaultExportFormat.toUpperCase(),
                              onTap: () => _pickOption(
                                context,
                                title: 'Default export format',
                                options: exportFormats,
                                current: settings.defaultExportFormat,
                                labelOf: (v) => v.toUpperCase(),
                                onSelected:
                                    settingsNotifier.setDefaultExportFormat,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.bolt_rounded,
                              title: 'Recurring quick-generate',
                              subtitle: 'One-tap generation from due templates',
                              trailing: Switch(
                                value: settings.recurringQuickGenerateEnabled,
                                onChanged: settingsNotifier
                                    .setRecurringQuickGenerateEnabled,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.bug_report_outlined,
                              title: 'Send crash reports',
                              subtitle:
                                  'The error and app version — no '
                                  'expenses, no message text',
                              trailing: Switch(
                                value: settings.errorReportsEnabled,
                                onChanged:
                                    settingsNotifier.setErrorReportsEnabled,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.savings_outlined,
                              title: 'Category budgets',
                              subtitle: _categoryBudgetsSubtitle(
                                ref.watch(categoryBudgetsProvider),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const ManageCategoryBudgetsScreen(),
                                ),
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.category_rounded,
                              title: 'Categories',
                              subtitle: 'Add, rename, restyle, or delete',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const ManageCategoriesScreen(),
                                ),
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.group_rounded,
                              title: 'People',
                              subtitle: 'Pin or hide split suggestions',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ManagePeopleScreen(),
                                ),
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.account_balance_wallet_rounded,
                              title: 'Payment methods',
                              subtitle: _defaultMethodSubtitle(
                                ref.watch(defaultPaymentMethodProvider),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const ManagePaymentMethodsScreen(),
                                ),
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.forum_rounded,
                              title: 'AI Assistant',
                              subtitle: aiConfigured
                                  ? 'Ask about spending, budget, history'
                                  : 'Sign in to enable AI features',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AiChatScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        _SettingsGroup(
                          stretch: isWide,
                          label: 'Reminders',
                          rows: [
                            _SettingRow(
                              icon: Icons.notifications_active_rounded,
                              title: 'Enable reminders',
                              trailing: Switch(
                                value: remindersOn,
                                onChanged: settingsNotifier.setRemindersEnabled,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.warning_amber_rounded,
                              title: 'Budget warnings',
                              trailing: Switch(
                                value: settings.budgetWarningReminderEnabled,
                                onChanged: remindersOn
                                    ? settingsNotifier
                                          .setBudgetWarningReminderEnabled
                                    : null,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.schedule_rounded,
                              title: 'Overdue receivables',
                              trailing: Switch(
                                value:
                                    settings.overdueReceivableReminderEnabled,
                                onChanged: remindersOn
                                    ? settingsNotifier
                                          .setOverdueReceivableReminderEnabled
                                    : null,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.repeat_rounded,
                              title: 'Recurring due',
                              trailing: Switch(
                                value: settings.recurringDueReminderEnabled,
                                onChanged: remindersOn
                                    ? settingsNotifier
                                          .setRecurringDueReminderEnabled
                                    : null,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.calendar_month_rounded,
                              title: 'Monthly budget',
                              trailing: Switch(
                                value: settings.monthlyBudgetReminderEnabled,
                                onChanged: remindersOn
                                    ? settingsNotifier
                                          .setMonthlyBudgetReminderEnabled
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      twoUp(
                        _SettingsGroup(
                          stretch: isWide,
                          label: 'Transactions',
                          rows: [
                            _SettingRow(
                              icon: Icons.sms_rounded,
                              title: 'Auto-detect from SMS',
                              subtitle:
                                  'Capture bank debits into a review list',
                              trailing: Switch(
                                value: settings.smsAutoDetectEnabled,
                                onChanged: (v) async {
                                  await settingsNotifier
                                      .setSmsAutoDetectEnabled(v);
                                  final sms = ref.read(
                                    smsCaptureServiceProvider,
                                  );
                                  if (v) {
                                    await sms.requestPermission();
                                  } else {
                                    // No detection, no notifications about it.
                                    await sms.setNotify(false);
                                  }
                                },
                              ),
                            ),
                            if (!kIsWeb &&
                                defaultTargetPlatform == TargetPlatform.android)
                              _SettingRow(
                                icon: Icons.notifications_active_rounded,
                                title: 'Notify on detection',
                                subtitle: 'Add or ignore from the notification',
                                trailing: Switch(
                                  value: settings.smsNotifyEnabled,
                                  onChanged: settings.smsAutoDetectEnabled
                                      ? (v) => _setSmsNotify(context, ref, v)
                                      : null,
                                ),
                              ),
                            if (ref.watch(isAuthenticatedProvider))
                              _SettingRow(
                                icon: Icons.phone_iphone_rounded,
                                title: 'Connect iPhone SMS',
                                subtitle: _iphoneSmsSubtitle(
                                  ref.watch(iphoneSmsHealthProvider),
                                ),
                                // Silence is the only symptom when iOS turns
                                // the automation off, so say it here.
                                subtitleColor:
                                    _iphoneSmsStale(
                                      ref.watch(iphoneSmsHealthProvider),
                                    )
                                    ? CalmColors.of(context).warning
                                    : null,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const IphoneSmsGuideScreen(),
                                  ),
                                ),
                              ),
                            if (kIsWeb)
                              _SettingRow(
                                icon: Icons.android_rounded,
                                title: 'Get the Android app',
                                subtitle:
                                    'Native app with automatic SMS detection',
                                onTap: () => launchUrl(
                                  Uri.parse(_androidAppUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                            _SettingRow(
                              icon: Icons.bug_report_rounded,
                              title: 'Simulate SMS (test)',
                              subtitle: 'Paste a bank SMS to test detection',
                              onTap: () => _showSimulateSmsDialog(context, ref),
                            ),
                            if (kIsWeb)
                              // Web had no version anywhere, so "is my browser
                              // running the latest build?" was unanswerable —
                              // a stale cached PWA looked identical to a
                              // feature that never shipped.
                              _SettingRow(
                                icon: Icons.public_rounded,
                                title: 'App version',
                                subtitle: 'v${appVersion ?? '…'} · web',
                                trailing: _PillButton(
                                  label: 'Reload',
                                  onTap: () => reloadForUpdate(),
                                ),
                              )
                            else
                              _SettingRow(
                                icon: Icons.system_update_rounded,
                                title: 'App version',
                                // Distinguishes "checked, you're current" from
                                // "couldn't reach GitHub" — the old row claimed
                                // up to date when the check had failed.
                                subtitle: updateVersion != null
                                    ? 'Update available — v${updateVersion.version}'
                                    : updateCheckFailed
                                    ? 'v${appVersion ?? '…'} · couldn\'t check'
                                    : 'v${appVersion ?? '…'} · up to date',
                                trailing: updateVersion != null
                                    ? _PillButton(
                                        label: 'Update',
                                        onTap: () => runAppUpdate(
                                          context,
                                          updateVersion,
                                        ),
                                      )
                                    : null,
                              ),
                          ],
                        ),
                        _SettingsGroup(
                          stretch: isWide,
                          label: 'Data & backup',
                          rows: [
                            _SettingRow(
                              icon: Icons.file_upload_outlined,
                              title: 'Export center',
                              subtitle: export.lastFile != null
                                  ? 'Last: ${export.lastFile!.fileName}'
                                  : null,
                              onTap: () => showExportModal(context),
                            ),
                            _SettingRow(
                              icon: Icons.backup_rounded,
                              title: 'Local backups',
                              subtitle: backups.backups.isEmpty
                                  ? 'No restore points yet'
                                  : '${backups.backups.length} restore '
                                        '${backups.backups.length == 1 ? 'point' : 'points'} · tap to restore',
                              trailing: backups.isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : _PillButton(
                                      label: 'Create',
                                      onTap: () =>
                                          backupNotifier.createBackup(),
                                    ),
                              onTap: () => _showBackupsSheet(
                                context,
                                backupNotifier,
                                backups.backups,
                              ),
                            ),
                            _SettingRow(
                              icon: Icons.ios_share_rounded,
                              title: 'Export / share backup',
                              subtitle: 'Save a restorable file off your phone',
                              onTap: backups.isLoading
                                  ? null
                                  : () => backupNotifier.exportBackupFile(),
                            ),
                            _SettingRow(
                              icon: Icons.file_open_rounded,
                              title: 'Import backup file',
                              onTap: backups.isLoading
                                  ? null
                                  : () => backupNotifier.importBackupFromFile(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start new salary cycle?'),
        content: const Text(
          'Dashboard and budget tracking restart from the date you pick. '
          'Previous records remain saved for history and analytics.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pick date'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Salary lands early some months and late others, so the cycle must be
    // able to start on the day the money actually arrived — not just today.
    final start = await _pickCycleStart(context, ref);
    if (start == null || !context.mounted) return;
    await ref
        .read(settingsProvider.notifier)
        .resetSalaryCycle(startDate: start);
    if (!context.mounted) return;
    await showCycleResetRecap(context, ref);
  }

  /// Date picker for a new cycle's first day, defaulting to the salary day
  /// this month when one is set, else today. Never allows a future start.
  static Future<DateTime?> _pickCycleStart(
    BuildContext context,
    WidgetRef ref,
  ) {
    final settings = ref.read(settingsProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var initial = today;
    final day = settings.salaryDay;
    if (day != null) {
      final lastDayOfMonth = DateTime(now.year, now.month + 1, 0).day;
      final thisMonth = DateTime(
        now.year,
        now.month,
        day.clamp(1, lastDayOfMonth),
      );
      if (!thisMonth.isAfter(today)) initial = thisMonth;
    }
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: today,
      helpText: 'Cycle starts on',
    );
  }

  static Future<void> _pickSalaryDay(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(settingsProvider).salaryDay;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Salary day'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Which day of the month does your salary usually land? Lekha '
              'only uses it to ask about starting a new cycle — you always '
              'confirm the real date.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            height: 260,
            width: 320,
            child: GridView.count(
              crossAxisCount: 6,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var day = 1; day <= 31; day++)
                  InkWell(
                    onTap: () => Navigator.of(ctx).pop(day),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: day == current
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: day == current
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (current != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(-1),
              child: const Text("Don't ask me"),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await ref
        .read(settingsProvider.notifier)
        .setSalaryDay(picked == -1 ? null : picked);
  }

  Future<void> _confirmRestore(
    BuildContext context,
    BackupNotifier backupNotifier,
    BackupMetadata item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          'This will replace your current local data with:\n'
          '${item.expenseCount} expenses, '
          '${item.receivableCount} receivables, '
          '${item.payableCount} payables, '
          '${item.recurringTemplateCount} recurring templates.\n\n'
          'This action cannot be undone (a safety snapshot is created '
          'automatically).\n\nBackup: ${item.backupId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await backupNotifier.restoreLocalBackup(item.backupId);
  }

  /// List local restore points; each restores via the existing confirm flow.
  void _showBackupsSheet(
    BuildContext context,
    BackupNotifier backupNotifier,
    List<BackupMetadata> items,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF131318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Local backups',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(
                  'No backups yet. Tap Create to make a restore point.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: Text(
                          'Backup · ${AppFormatters.getRelativeTime(item.createdAt)}',
                        ),
                        subtitle: Text(
                          '${item.expenseCount} exp · ${item.receivableCount} recv · ${item.payableCount} pay',
                        ),
                        trailing: _PillButton(
                          label: 'Restore',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _confirmRestore(context, backupNotifier, item);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

Future<void> _pickOption(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String current,
  required ValueChanged<String> onSelected,
  String Function(String)? labelOf,
}) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF131318),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                title,
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final option in options)
              ListTile(
                title: Text(labelOf?.call(option) ?? option),
                trailing: option == current
                    ? Icon(Icons.check_rounded, color: cs.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (selected != null) onSelected(selected);
}

/// Edit the dashboard-greeting display name.
Future<void> _editDisplayName(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController(
    text: ref.read(settingsProvider).displayName,
  );
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Display name'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Your name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) {
    await ref.read(settingsProvider.notifier).setDisplayName(name);
  }
}

/// Debug: run a pasted SMS body through the detection pipeline.
Future<void> _showSimulateSmsDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final body = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Simulate SMS'),
      content: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 6,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Paste a bank SMS body…'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Run'),
        ),
      ],
    ),
  );
  if (body == null || body.trim().isEmpty) return;
  final added = await ref.read(smsCaptureServiceProvider).simulate(body.trim());
  ref.read(pendingTransactionsProvider.notifier).refresh();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        added
            ? 'Detected — see the "Detected" section in Expenses.'
            : 'Not a debit, or no amount found.',
      ),
    ),
  );
}

String _defaultMethodSubtitle(String? method) =>
    method == null ? 'Edit the list, pick a default' : 'Default: $method';

/// Store the toggle, mirror it to the native receiver, and say so when Android
/// withholds the permission — otherwise the switch reads "on" while nothing
/// ever arrives.
Future<void> _setSmsNotify(BuildContext context, WidgetRef ref, bool on) async {
  await ref.read(settingsProvider.notifier).setSmsNotifyEnabled(on);
  final allowed = await ref.read(smsCaptureServiceProvider).setNotify(on);
  if (!on || allowed || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Allow notifications for Lekha in system settings to get these.',
      ),
    ),
  );
}

String _categoryBudgetsSubtitle(Map<String, double> budgets) {
  if (budgets.isEmpty) return 'Cap the categories that get away from you';
  final total = budgets.values.fold<double>(0, (sum, v) => sum + v);
  final count = budgets.length;
  return '$count ${count == 1 ? 'category' : 'categories'} capped · '
      '${AppFormatters.formatCurrency(total)} a cycle';
}

String _formatCycleDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

/// "7th", "1st", "22nd" — used wherever the salary day is shown.
String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  switch (day % 10) {
    case 1:
      return '${day}st';
    case 2:
      return '${day}nd';
    case 3:
      return '${day}rd';
    default:
      return '${day}th';
  }
}

/// A tiny uppercase section label above a frosted card of rows.
class _SettingsGroup extends StatelessWidget {
  final String label;
  final List<Widget> rows;

  /// True inside the desktop IntrinsicHeight pairs: the card fills the row
  /// height so paired groups share a bottom edge. Must stay a plain flag —
  /// a LayoutBuilder here would report zero intrinsic height in release
  /// builds and collapse the row.
  final bool stretch;

  const _SettingsGroup({
    required this.label,
    required this.rows,
    this.stretch = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divided = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        divided.add(
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        );
      }
      divided.add(rows[i]);
    }

    final card = GlassCard(
      radius: 12,
      padding: EdgeInsets.zero,
      child: Column(children: divided),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                color: cs.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ),
          if (stretch) Expanded(child: card) else card,
        ],
      ),
    );
  }
}

/// One compact settings row: leading icon, title (+ optional subtitle), and a
/// trailing control — a value+chevron (tappable), a switch, or a pill button.
/// iOS turns Shortcuts automations off without telling anyone, and the only
/// symptom is that detections quietly stop. Three days of silence from a
/// previously-working setup is worth flagging on the Settings row itself.
const _kIphoneSmsStaleAfter = Duration(days: 3);

bool _iphoneSmsStale(AsyncValue<DateTime?> health) {
  final last = health.valueOrNull;
  if (last == null) return false;
  return DateTime.now().difference(last) > _kIphoneSmsStaleAfter;
}

String _iphoneSmsSubtitle(AsyncValue<DateTime?> health) {
  final last = health.valueOrNull;
  if (health.isLoading) return 'Step-by-step Shortcuts setup guide';
  if (last == null) return 'Step-by-step Shortcuts setup guide';
  final ago = DateTime.now().difference(last);
  if (ago > _kIphoneSmsStaleAfter) {
    return 'No SMS for ${AppFormatters.getRelativeTime(last)} — the iPhone '
        'automation may have switched itself off';
  }
  return 'Working · last SMS ${AppFormatters.getRelativeTime(last)}';
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Lets a row raise its own alarm (e.g. iPhone SMS capture gone quiet).
  final Color? subtitleColor;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final showChevron = onTap != null && trailing == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 19, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: subtitleColor ?? cs.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 10),
                Text(
                  value!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              if (trailing != null)
                trailing!
              else if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small bordered violet pill button (Reset / Restore).
class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
