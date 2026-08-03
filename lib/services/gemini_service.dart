import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/history/cycle_history_snapshot.dart';
import 'supabase/supabase_service.dart';

class GeminiService {
  /// The user's currency code (e.g. 'INR'). Injected into every prompt so
  /// models don't guess bare numbers or default to dollars.
  final String currency;

  GeminiService({this.currency = 'INR'});

  /// AI calls go through the `gemini-proxy` Edge Function (JWT-verified), so
  /// the Gemini key lives server-side and never ships in the app bundle.
  /// Configured = Supabase reachable + a signed-in session to authenticate as.
  bool get isConfigured {
    final url = dotenv.env['SUPABASE_URL'];
    if (url == null || url.trim().isEmpty) return false;
    try {
      return SupabaseService.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<String> summarizeAnalytics({
    required String period,
    required double totalSpent,
    required double averageDaily,
    required String? topCategory,
    required double? topCategoryAmount,
    required double budget,
    required double remaining,
    required double projectedSpend,
  }) async {
    return _generateText(
      systemInstruction:
          'You are a concise personal finance assistant. Reply in 2 to 3 short '
          'plain-text sentences. Do not use markdown, asterisks, bold, bullet '
          'symbols, numbering, or headings.',
      userPrompt:
          'Summarize this spending analysis.\n'
          'Period: $period\n'
          'Total spent: $totalSpent\n'
          'Average daily: $averageDaily\n'
          'Top category: ${topCategory ?? 'None'}\n'
          'Top category amount: ${topCategoryAmount ?? 0.0}\n'
          'Budget: $budget\n'
          'Remaining: $remaining\n'
          'Projected spend: $projectedSpend\n'
          'Focus on trends, risk, and one practical action.',
    );
  }

  Future<String> summarizeCycleHistory(CycleHistorySnapshot snapshot) async {
    final categories = snapshot.categoryBreakdown.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    return _generateText(
      systemInstruction:
          'You summarize past salary cycles. Keep it compact, factual, and '
          'helpful. Reply in plain-text sentences with no markdown, asterisks, '
          'bold, bullet symbols, numbering, or headings.',
      userPrompt:
          'Summarize this past cycle.\n'
          'Cycle start: ${snapshot.cycleStartDate.toIso8601String()}\n'
          'Cycle end: ${snapshot.cycleEndDate.toIso8601String()}\n'
          'Total expenses: ${snapshot.totalExpenses}\n'
          'Budget: ${snapshot.cycleBudget}\n'
          'Salary: ${snapshot.cycleSalary}\n'
          'Transaction count: ${snapshot.transactionCount}\n'
          'Category breakdown: $categories\n'
          'Return a short summary and one takeaway.',
    );
  }

  Future<String> summarizeDashboard({
    required double cycleSpend,
    required double budget,
    required double salary,
    required double receivables,
    required double payables,
    required int transactionCount,
    required int overdueDebtCount,
  }) async {
    return _generateText(
      systemInstruction:
          'You provide dashboard recommendations for a finance tracker. Be '
          'concise and action-oriented. Reply as 2 to 3 short plain-text '
          'sentences, one per line. Do not use markdown, asterisks, bold, '
          'bullet symbols, numbering, or headings.',
      userPrompt:
          'Give 2 to 3 short recommendations from this dashboard state.\n'
          'Cycle spend: $cycleSpend\n'
          'Budget: $budget\n'
          'Salary: $salary\n'
          'Receivables: $receivables\n'
          'Payables: $payables\n'
          'Transaction count: $transactionCount\n'
          'Overdue debt count: $overdueDebtCount',
    );
  }

  Future<String> suggestExpenseCategory({
    required List<String> categories,
    required String notes,
    required double? amount,
  }) async {
    return _generateText(
      systemInstruction:
          'Choose exactly one category from the allowed list. Respond with the category only.',
      userPrompt:
          'Allowed categories: ${categories.join(', ')}\n'
          'Expense notes: $notes\n'
          'Amount: ${amount ?? 0.0}\n'
          'Return only the single best category.',
    );
  }

  /// Ask Gemini to pick an icon (from [iconKeys]) and a hex color for a new
  /// category. Returns `{'icon': key, 'color': '#RRGGBB'}`. The caller is
  /// responsible for validating the values against the allowlist.
  Future<Map<String, String>> suggestCategoryStyle({
    required String name,
    required List<String> iconKeys,
  }) async {
    final raw = await _generateText(
      systemInstruction:
          'You assign a visual style to a personal-finance expense category. '
          'Respond with ONLY compact JSON and nothing else, in the exact form '
          '{"icon":"<one key copied verbatim from the allowed list>","color":"#RRGGBB"}. '
          'Pick the icon whose meaning best matches the category name and a calm, muted color.',
      userPrompt:
          'Category name: $name\n'
          'Allowed icon keys: ${iconKeys.join(', ')}\n'
          'Return only the JSON object.',
    );
    final decoded = jsonDecode(_extractJson(raw)) as Map<String, dynamic>;
    return {
      'icon': (decoded['icon'] as String? ?? '').trim(),
      'color': (decoded['color'] as String? ?? '').trim(),
    };
  }

  /// Pull the first JSON object out of a model reply, tolerating code fences
  /// or surrounding prose.
  String _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw Exception('Gemini returned no JSON object');
    }
    return raw.substring(start, end + 1);
  }

  /// Feature 2: parse a free-text/voice phrase into one expense. Returns
  /// `{amount, category, note, date (YYYY-MM-DD), paymentMethod}`; the caller
  /// validates category/paymentMethod against its allowed lists.
  Future<Map<String, dynamic>> parseExpenseFromText({
    required String text,
    required List<String> categories,
    required List<String> paymentMethods,
    required String todayIso,
  }) async {
    final raw = await _generateText(
      systemInstruction:
          'Extract ONE expense from the user text. Respond with ONLY compact JSON: '
          '{"amount":number,"category":"<one of the allowed categories, else empty>",'
          '"note":"<short description>","date":"YYYY-MM-DD",'
          '"paymentMethod":"<one of the allowed methods, else empty>"}. '
          'Resolve relative dates like "today"/"yesterday" against the given today date. '
          'Unknown fields: empty string, or 0 for amount.',
      userPrompt:
          'Today: $todayIso\n'
          'Allowed categories: ${categories.join(', ')}\n'
          'Allowed payment methods: ${paymentMethods.join(', ')}\n'
          'Text: $text\n'
          'Return only the JSON.',
    );
    return jsonDecode(_extractJson(raw)) as Map<String, dynamic>;
  }

  /// SMS auto-detect: pull just the debited amount out of a bank/UPI SMS.
  /// Returns `{isFinancial: bool, isDebit: bool, amount: number}`. Date/time
  /// come from the SMS timestamp, so we don't ask for them here.
  Future<Map<String, dynamic>> parseSmsTransaction(
    String body, {
    String? todayIso,
  }) async {
    final today = todayIso ?? DateTime.now().toIso8601String().split('T').first;
    final raw = await _generateText(
      systemInstruction:
          'You read ONE bank or UPI SMS and extract the transaction amount '
          'and, when the message states it, when it happened. '
          'Respond with ONLY compact JSON: '
          '{"isFinancial":bool,"isDebit":bool,"amount":number,'
          '"when":string|null}. '
          'isFinancial=false for OTP, promotional, balance-only, EMI-due, or '
          'delivery messages. isDebit=true only when money LEFT the account '
          '(debited / spent / paid / sent / withdrawn); false for credits, '
          'refunds, or received money. amount is the transaction amount, NOT '
          'the available balance; use 0 if unclear. '
          '"when" is the transaction date (and time if given) as an ISO 8601 '
          'string, resolving 2-digit years and formats like 01-08-26 or '
          '"on 30Jul25 14:22"; today is $today. Use null when the message '
          'does not state a date — never guess.',
      userPrompt: 'SMS: $body\nReturn only the JSON.',
    );
    return jsonDecode(_extractJson(raw)) as Map<String, dynamic>;
  }

  /// Feature 5: one short, friendly sentence warning about a possibly
  /// unintended expense (duplicate or unusually high). Plain text, no JSON.
  Future<String> explainSpendingWarning({
    required String kind, // 'duplicate' | 'anomaly'
    required String category,
    required double amount,
    required double typical,
  }) async {
    return _generateText(
      systemInstruction:
          'You warn a user about a possibly unintended expense in ONE short, '
          'friendly sentence. No preamble, no lists.',
      userPrompt: kind == 'duplicate'
          ? 'A new $category expense of $amount matches one already added today. '
                'Warn it might be a duplicate.'
          : 'A new $category expense of $amount is much higher than the usual '
                '$typical for $category this cycle. Warn that it looks unusually high.',
    );
  }

  /// Draft a warm, low-pressure reminder that a friend owes you money. No
  /// name is used (the user picks the contact when sharing), and the total +
  /// item breakdown are woven into 2 to 3 friendly sentences. [language] is
  /// one of 'English', 'Hinglish', or 'Hindi'.
  Future<String> draftDebtReminder({
    required String total,
    required List<String> items,
    String language = 'English',
  }) async {
    const styles = {
      'Hinglish':
          'Write in Hinglish — casual Hindi written in Roman/English letters '
          '(e.g. "thoda sa reminder tha"). Keep the amount in digits.',
      'Hindi':
          'Write in natural Hindi using Devanagari script. Keep the amount in '
          'digits with the ₹ symbol.',
      'English': 'Write in friendly English.',
    };
    return _generateText(
      systemInstruction:
          'You write a short, warm, low-pressure reminder that a friend still '
          'owes the sender some money. Be gentle and casual, never demanding. '
          'You MUST state the exact amount owed verbatim as given. '
          'Do NOT address anyone by name or use a placeholder like [Name]. '
          '2 to 3 short plain-text sentences. No markdown, bullets, or headings. '
          'Each time, reframe the sentences with fresh wording and tone. '
          '${styles[language] ?? styles['English']}',
      temperature: 1.1,
      userPrompt:
          'Amount owed (include this exactly): $total\n'
          '${items.isEmpty ? '' : 'For:\n${items.join('\n')}\n'}'
          'Write a fresh, differently-worded reminder message.',
    );
  }

  Future<String> chat({
    required String userMessage,
    required Map<String, dynamic> financeContext,
  }) async {
    return _generateText(
      systemInstruction:
          'You are an in-app finance assistant. Either answer briefly in plain text, '
          'OR perform ONE action by replying with ONLY a JSON object (no prose), one of:\n'
          '{"action":"add_expense","amount":number,"category":string,"note":string,"date":"YYYY-MM-DD","paymentMethod":string}\n'
          '{"action":"mark_payable_paid","payee":string}\n'
          '{"action":"set_budget","amount":number}\n'
          'Use an action ONLY when the user clearly asks to add an expense, mark a payable paid, '
          'or set the budget; pick category from the allowed list in the context. '
          'Otherwise answer in plain text. Never mix prose and JSON.',
      userPrompt:
          'App context: ${jsonEncode(financeContext)}\n'
          'User: $userMessage',
    );
  }

  Future<String> _generateText({
    required String systemInstruction,
    required String userPrompt,
    double temperature = 0.4,
  }) async {
    final baseUrl = dotenv.env['SUPABASE_URL'];
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      throw Exception('AI is not configured');
    }
    String? token;
    try {
      token = SupabaseService.client.auth.currentSession?.accessToken;
    } catch (_) {}
    if (token == null) {
      throw Exception('Sign in to use AI features');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/functions/v1/gemini-proxy'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      },
      body: jsonEncode({
        // Every feature shares this: without it Gemini writes bare numbers
        // and Llama guesses dollars.
        'system':
            '$systemInstruction\n'
            'All monetary amounts are in $currency. Always write amounts '
            'with the matching currency symbol.',
        'prompt': userPrompt,
        'temperature': temperature,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception('AI request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = decoded['text'] as String? ?? '';
    if (text.trim().isEmpty) {
      throw Exception('AI returned blank text');
    }
    return text.trim();
  }
}
