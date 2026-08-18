import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/expense/expense_model.dart';
import '../models/history/cycle_history_snapshot.dart';
import '../models/payable/payable_model.dart';
import '../providers/auth/auth_provider.dart';
import '../providers/budget/budget_providers.dart';
import '../providers/debt/debt_providers.dart';
import '../providers/storage/storage_providers.dart';
import '../screens/analytics/providers/analytics_providers.dart';
import '../screens/dashboard/providers/dashboard_providers.dart';
import '../screens/expenses/providers/expenses_providers.dart';
import '../screens/history_providers.dart';
import '../screens/settings/providers/settings_providers.dart';
import '../providers/payment/payment_method_providers.dart';
import '../services/gemini_service.dart';
import '../services/storage/hive_service.dart' show kLocalPrefsBox;
import '../utils/formatters/formatters.dart';

class AiChatMessage {
  final String role;
  final String text;

  const AiChatMessage({required this.role, required this.text});
}

/// What the confirm card says before an expense is written from chat. Pure so
/// the wording — the only thing standing between a misread amount and the
/// ledger — can be tested without a model in the loop.
String summarizeAddExpense(Map<String, dynamic> action, String? category) {
  final amount = (action['amount'] as num?)?.toDouble() ?? 0;
  final parts = <String>[
    'Add ${AppFormatters.formatCurrency(amount)}',
    if (category != null) 'to $category',
  ];
  final note = (action['note'] as String? ?? '').trim();
  if (note.isNotEmpty) parts.add('for $note');
  final date = DateTime.tryParse(action['date'] as String? ?? '');
  if (date != null) parts.add('on ${DateFormat('d MMM').format(date)}');
  final method = (action['paymentMethod'] as String? ?? '').trim();
  if (method.isNotEmpty) parts.add('via $method');
  return parts.join(' ');
}

/// A money-mutating chat action awaiting the user's confirmation.
class PendingAction {
  final String action; // 'mark_payable_paid' | 'set_budget'
  final Map<String, dynamic> args;
  final String summary;

  const PendingAction({
    required this.action,
    required this.args,
    required this.summary,
  });
}

class AiChatState {
  static const Object _keep = Object();

  final bool isLoading;
  final String? error;
  final List<AiChatMessage> messages;
  final PendingAction? pending;

  const AiChatState({
    this.isLoading = false,
    this.error,
    this.messages = const [],
    this.pending,
  });

  AiChatState copyWith({
    bool? isLoading,
    String? error,
    List<AiChatMessage>? messages,
    Object? pending = _keep,
  }) {
    return AiChatState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      messages: messages ?? this.messages,
      pending: pending == _keep ? this.pending : pending as PendingAction?,
    );
  }
}

final geminiServiceProvider = Provider(
  (ref) => GeminiService(
    currency: ref.watch(settingsProvider.select((s) => s.currency)),
  ),
);

final geminiConfiguredProvider = Provider<bool>((ref) {
  return ref.watch(geminiServiceProvider).isConfigured;
});

final analyticsAiSummaryProvider = FutureProvider.family<String?, String>((
  ref,
  userId,
) async {
  final service = ref.watch(geminiServiceProvider);
  if (!service.isConfigured) {
    return null;
  }
  final summary = ref.watch(analyticsSummaryProvider(userId));
  final budgetInsight = ref.watch(analyticsBudgetInsightProvider(userId));
  // The model must name the same window the cards show, or its "this month"
  // contradicts a screen reading "This cycle".
  final scope = ref.watch(analyticsScopeProvider);
  return service.summarizeAnalytics(
    period: scope.label,
    totalSpent: summary.totalSpent,
    averageDaily: summary.averageDaily,
    topCategory: summary.topCategory?.category,
    topCategoryAmount: summary.topCategory?.amount,
    budget: budgetInsight.budget,
    remaining: budgetInsight.remaining,
    projectedSpend: budgetInsight.projected,
  );
});

final dashboardAiSummaryProvider = FutureProvider.family<String?, String>((
  ref,
  userId,
) async {
  final service = ref.watch(geminiServiceProvider);
  if (!service.isConfigured) {
    return null;
  }
  final monthlySpend = ref.watch(monthlySpendProvider(userId));
  final budgetMetrics = ref.watch(budgetMetricsProvider(userId));
  final receivables = ref.watch(receivablesTotalProvider(userId));
  final payables = ref.watch(totalPayablesProvider(userId));
  final transactions = ref.watch(transactionCountProvider(userId));
  final overdue = ref.watch(overdueDebtCountProvider(userId));
  return service.summarizeDashboard(
    cycleSpend: monthlySpend,
    budget: budgetMetrics.budget,
    salary: budgetMetrics.salary,
    receivables: receivables,
    payables: payables,
    transactionCount: transactions,
    overdueDebtCount: overdue,
  );
});

final historyAiSummaryProvider =
    FutureProvider.family<String?, CycleHistorySnapshot>((ref, snapshot) async {
      final service = ref.watch(geminiServiceProvider);
      if (!service.isConfigured) {
        return null;
      }
      return service.summarizeCycleHistory(snapshot);
    });

class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  AiChatNotifier(this._ref)
    : super(AiChatState(messages: _loadPersistedMessages()));

  /// History survives reloads on this device (device-local by design — the
  /// box is excluded from cloud sync). Box-open guard keeps tests working.
  static List<AiChatMessage> _loadPersistedMessages() {
    if (!Hive.isBoxOpen(kLocalPrefsBox)) return const [];
    final raw = Hive.box(kLocalPrefsBox).get('chatMessages');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (m) => AiChatMessage(
            role: m['role']?.toString() ?? 'assistant',
            text: m['text']?.toString() ?? '',
          ),
        )
        .toList();
  }

  /// Every state change persists the transcript (capped at the last 50).
  @override
  set state(AiChatState value) {
    super.state = value;
    if (!Hive.isBoxOpen(kLocalPrefsBox)) return;
    final msgs = value.messages.length > 50
        ? value.messages.sublist(value.messages.length - 50)
        : value.messages;
    Hive.box(kLocalPrefsBox).put('chatMessages', [
      for (final m in msgs) {'role': m.role, 'text': m.text},
    ]);
  }

  Future<void> send(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final service = _ref.read(geminiServiceProvider);
    if (!service.isConfigured) {
      state = state.copyWith(error: 'Gemini is not configured');
      return;
    }

    final userId = _ref.read(currentUserIdProvider) ?? '';
    final summary = _ref.read(analyticsSummaryProvider(userId));
    final budgetMetrics = _ref.read(budgetMetricsProvider(userId));
    final history = _ref.read(cycleHistoryProvider(userId));

    final nextMessages = [
      ...state.messages,
      AiChatMessage(role: 'user', text: trimmed),
    ];
    state = state.copyWith(
      isLoading: true,
      error: null,
      messages: nextMessages,
    );

    try {
      final reply = await service.chat(
        userMessage: trimmed,
        financeContext: {
          'totalSpent': summary.totalSpent,
          'averageDaily': summary.averageDaily,
          'budget': budgetMetrics.budget,
          'salary': budgetMetrics.salary,
          'remaining': budgetMetrics.remaining,
          'historyCycles': history.length,
          'categories': _ref.read(expenseCategoriesProvider),
        },
      );
      await _handleReply(reply, userId, nextMessages);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Feature 7: run an action if the reply is an action JSON, else show text.
  Future<void> _handleReply(
    String reply,
    String userId,
    List<AiChatMessage> baseMessages,
  ) async {
    final action = _tryParseAction(reply);

    // Everything that writes money waits for a yes. add_expense used to go
    // straight in as "additive, trivially undone" — but a misread amount or
    // category books wrong data silently, and undoing it means hunting the row
    // down in the list.
    if (action != null &&
        (action['action'] == 'add_expense' ||
            action['action'] == 'mark_payable_paid' ||
            action['action'] == 'set_budget')) {
      final summary = _summarizeAction(action);
      state = state.copyWith(
        isLoading: false,
        messages: [
          ...baseMessages,
          AiChatMessage(role: 'assistant', text: '$summary?'),
        ],
        pending: PendingAction(
          action: action['action'] as String,
          args: action,
          summary: summary,
        ),
      );
      return;
    }

    _finishWithAssistant(baseMessages, reply.trim());
  }

  void _finishWithAssistant(List<AiChatMessage> baseMessages, String text) {
    state = state.copyWith(
      isLoading: false,
      messages: [
        ...baseMessages,
        AiChatMessage(role: 'assistant', text: text),
      ],
    );
  }

  Map<String, dynamic>? _tryParseAction(String reply) {
    final trimmed = reply.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic> && decoded['action'] is String) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  String _summarizeAction(Map<String, dynamic> action) {
    switch (action['action']) {
      case 'add_expense':
        return summarizeAddExpense(
          action,
          _match(_ref.read(expenseCategoriesProvider), action['category']),
        );
      case 'mark_payable_paid':
        return 'Mark ${action['payee'] ?? 'this payable'} as paid';
      case 'set_budget':
        return 'Set the cycle budget to '
            '${AppFormatters.formatCurrency((action['amount'] as num?)?.toDouble() ?? 0)}';
      default:
        return 'Perform this action';
    }
  }

  Future<String> _addExpense(Map<String, dynamic> action, String userId) async {
    final amount = (action['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) {
      return "I couldn't read an amount, so nothing was added.";
    }
    final categories = _ref.read(expenseCategoriesProvider);
    final category = _match(categories, action['category']) ?? 'Miscellaneous';
    final note = (action['note'] as String? ?? '').trim();
    final date =
        DateTime.tryParse(action['date'] as String? ?? '') ?? DateTime.now();
    // The model is asked for a payment method and this used to throw it away,
    // so every chat-added expense landed untagged while the add sheet tagged
    // one by default — and the by-method breakdown quietly under-counted.
    final method = resolveAutoPaymentMethod(
      _match(_ref.read(paymentMethodsProvider), action['paymentMethod']),
      _ref.read(defaultPaymentMethodProvider),
    );
    final expense = Expense(
      id: const Uuid().v4(),
      userId: userId,
      amount: amount,
      category: category,
      description: note.isEmpty ? null : note,
      date: date,
      paymentMethod: method,
      createdAt: DateTime.now(),
    );
    await _ref.read(expensesProvider.notifier).addExpense(expense);
    return 'Added ${AppFormatters.formatCurrency(amount)} to $category.';
  }

  Future<String> _markPayablePaid(Map<String, dynamic> action) async {
    final name = (action['payee'] as String? ?? '').trim().toLowerCase();
    Payable? match;
    for (final payable in _ref.read(payablesProvider).payables) {
      if (payable.remainingAmount <= 0) continue;
      if (name.isEmpty || payable.toPerson.toLowerCase().contains(name)) {
        match = payable;
        break;
      }
    }
    if (match == null) {
      return "I couldn't find an unpaid payable matching '${action['payee'] ?? ''}'.";
    }
    await _ref.read(payablesProvider.notifier).markPayablePaid(match.id);
    return "Marked ${match.toPerson}'s payable as paid.";
  }

  Future<String> _setBudget(Map<String, dynamic> action) async {
    final amount = (action['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return "I couldn't read a valid budget amount.";
    await _ref.read(settingsProvider.notifier).setCycleBudget(amount);
    return 'Cycle budget set to ${AppFormatters.formatCurrency(amount)}.';
  }

  String? _match(List<String> options, dynamic value) {
    final target = (value as String? ?? '').trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final option in options) {
      if (option.toLowerCase() == target) return option;
    }
    return null;
  }

  Future<void> confirmPending() async {
    final pending = state.pending;
    if (pending == null) return;
    state = state.copyWith(pending: null, isLoading: true);
    String result;
    try {
      result = switch (pending.action) {
        'add_expense' => await _addExpense(
          pending.args,
          _ref.read(currentUserIdProvider) ?? '',
        ),
        'set_budget' => await _setBudget(pending.args),
        _ => await _markPayablePaid(pending.args),
      };
    } catch (e) {
      result = 'Could not complete that: $e';
    }
    state = state.copyWith(
      isLoading: false,
      messages: [
        ...state.messages,
        AiChatMessage(role: 'assistant', text: result),
      ],
    );
  }

  void cancelPending() {
    if (state.pending == null) return;
    state = state.copyWith(
      pending: null,
      messages: [
        ...state.messages,
        const AiChatMessage(role: 'assistant', text: 'Okay, cancelled.'),
      ],
    );
  }

  void clear() {
    state = const AiChatState();
  }
}

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((
  ref,
) {
  return AiChatNotifier(ref);
});
