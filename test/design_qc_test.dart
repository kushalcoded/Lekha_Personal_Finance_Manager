@Tags(['design'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Transitive via supabase_flutter; Supabase.initialize needs its store mocked.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/navigation/app_shell.dart';
import 'package:personal_expanse_tracker/models/pending/pending_transaction.dart';
import 'package:personal_expanse_tracker/models/receivable/receivable_model.dart';
import 'package:personal_expanse_tracker/models/payable/payable_model.dart';
import 'package:personal_expanse_tracker/providers/ai_providers.dart';
import 'package:personal_expanse_tracker/providers/auth/auth_provider.dart';
import 'package:personal_expanse_tracker/providers/sms/sms_providers.dart';
import 'package:personal_expanse_tracker/providers/storage/storage_providers.dart';
import 'package:personal_expanse_tracker/screens/settings/providers/settings_providers.dart';
import 'package:personal_expanse_tracker/screens/analytics/analytics_screen.dart';
import 'package:personal_expanse_tracker/screens/auth/login_screen.dart';
import 'package:personal_expanse_tracker/screens/dashboard/dashboard_screen.dart';
import 'package:personal_expanse_tracker/screens/debts/debts_screen.dart';
import 'package:personal_expanse_tracker/screens/debts/person_ledger_screen.dart';
import 'package:personal_expanse_tracker/screens/expenses/expenses_screen.dart';
import 'package:personal_expanse_tracker/providers/clock_provider.dart';
import 'package:personal_expanse_tracker/screens/expenses/widgets/add_expense_modal.dart';
import 'package:personal_expanse_tracker/screens/settings/settings_screen.dart';
import 'package:personal_expanse_tracker/services/storage/hive_service.dart';
import 'package:personal_expanse_tracker/services/supabase/supabase_service.dart';
import 'package:personal_expanse_tracker/theme/app_theme.dart';
import 'package:personal_expanse_tracker/widgets/common/ambient_background.dart';

/// Renders every designed surface to PNG so the Midnight Terminal design can
/// be reviewed as pixels, not just code. Run with:
///
///   flutter test test/design_qc_test.dart --update-goldens
///
/// Tagged `design` and excluded from the default suite (see dart_test.yaml)
/// because goldens are platform/font-sensitive and would be brittle in CI.
const _userId = 'qc-user';

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);

/// Icon font ships with the SDK, not the app — without it every icon paints
/// as a tofu box.
String? _materialIconsPath() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    '${flutterRoot ?? ''}/bin/cache/artifacts/material_fonts/'
        'materialicons-regular.otf',
    'C:/Users/Admin/develop/bin/cache/artifacts/material_fonts/'
        'materialicons-regular.otf',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

Future<void> _loadFonts() async {
  final fonts = {
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'Space Grotesk': 'assets/fonts/SpaceGrotesk-Variable.ttf',
    'JetBrains Mono': 'assets/fonts/JetBrainsMono-Variable.ttf',
  };
  final icons = _materialIconsPath();
  if (icons != null) fonts['MaterialIcons'] = icons;
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(
        File(entry.value).readAsBytes().then((b) => b.buffer.asByteData()),
      );
    await loader.load();
  }
}

/// The one instant the harness pins: only the dashboard's weekday reads it, so
/// nothing here depends on the app agreeing about what day it is. Seeded data
/// stays relative to the real clock — the app's cycle, day headers and charts
/// all compute against `DateTime.now()`, and freezing the data instead of the
/// app just put every expense outside the current cycle.
final _qcNow = DateTime(2026, 1, 15, 10, 30);

Future<void> _seed() async {
  final hive = HiveService();
  final now = DateTime.now();
  DateTime day(int back) => now.subtract(Duration(days: back));

  await hive.setMonthlyBudget(_userId, now, 20000);
  await hive.saveSettings(_userId, {
    'displayName': 'Kushal',
    'currentCycleBudget': 20000.0,
    'currentCycleSalary': 40000.0,
    // A fixed offset, not the 1st of the month: the chip prints the day number,
    // which counted up by one every day and re-shot six goldens with it. The
    // stored key is salaryCycleStartDate — `currentCycleStartDate` is a getter,
    // so seeding that name did nothing at all.
    'salaryCycleStartDate': day(12).toIso8601String(),
  });

  final expenses = [
    ('Swiggy', 'Food', 289.0, 'GPay', 0),
    ('Blinkit', 'Shopping', 412.0, 'GPay', 0),
    ('Metro card', 'Transport', 60.0, 'Card', 1),
    ('Electricity bill', 'Bills', 1240.0, 'Bank Transfer', 1),
    ('Dinner · Split ₹238.80', 'Food', 119.40, 'GPay', 2),
    ('SIP', 'Investment', 4800.0, 'Bank Transfer', 3),
    ('Movie night', 'Entertainment', 640.0, 'Card', 4),
    ('Chai', 'Food', 40.0, 'Cash', 5),
  ];
  for (var i = 0; i < expenses.length; i++) {
    final (desc, cat, amount, method, back) = expenses[i];
    await hive.addExpense(
      Expense(
        id: 'exp_$i',
        userId: _userId,
        amount: amount,
        category: cat,
        description: desc,
        paymentMethod: method,
        date: day(back),
        createdAt: day(back),
        updatedAt: day(back),
      ),
    );
  }

  final receivables = [
    ('Rahul', 300.0, 'Dinner split · Pizza night', 13, false),
    ('Rahul', 150.0, 'Auto fare', 7, false),
    ('Rahul', 500.0, 'Movie tickets', 21, true),
    ('Priya', 800.0, 'Concert ticket', 4, false),
  ];
  for (var i = 0; i < receivables.length; i++) {
    final (person, amount, note, back, paid) = receivables[i];
    await hive.addReceivable(
      Receivable(
        id: 'rec_$i',
        userId: _userId,
        fromPerson: person,
        amount: amount,
        description: note,
        dueDate: day(back - 3),
        isPaid: paid,
        remainingAmount: paid ? 0 : amount,
        createdAt: day(back),
        updatedAt: day(back),
      ),
    );
  }

  await hive.addPayable(
    Payable(
      id: 'pay_0',
      userId: _userId,
      toPerson: 'Aman',
      amount: 300,
      remainingAmount: 300,
      category: 'Friends',
      notes: 'Cab share',
      dueDate: day(2),
      status: PayableStatus.pending,
      settlements: const [],
      createdAt: day(6),
      updatedAt: day(6),
    ),
  );

  // Detected cards print an absolute timestamp, so these two are the one thing
  // seeded at a fixed instant — a relative one re-shot every screen that shows
  // a detection, which is most of them.
  await hive.savePendingTransaction(
    PendingTransaction(
      id: 'pending_0',
      amount: 450,
      dateTime: _qcNow,
      rawBody: 'HDFC Bank: Rs.450 debited via UPI',
      createdAt: _qcNow,
    ),
  );
  await hive.savePendingTransaction(
    PendingTransaction(
      id: 'pending_1',
      amount: 2000,
      dateTime: _qcNow.subtract(const Duration(hours: 2)),
      rawBody: 'SBI: Rs.2000 withdrawn at ATM',
      createdAt: _qcNow,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();

    // Hive stores under a scratch dir: initFlutter() asks path_provider for
    // the documents dir, which has no implementation under flutter_test.
    final dir = await Directory.systemTemp.createTemp('lekha_qc');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(
      fileInput:
          'SUPABASE_URL=http://localhost:54321\n'
          'SUPABASE_ANON_KEY=qc-anon-key',
    );
    await SupabaseService.initialize();
    await HiveService.initialize();
    await _seed();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = _phone,
    double textScale = 1.0,
    Duration settle = const Duration(milliseconds: 400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // Screens read from in-memory stores that main.dart normally fills on
    // launch, so prime them before the first frame.
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        geminiConfiguredProvider.overrideWithValue(false),
        nowProvider.overrideWithValue(() => _qcNow),
      ],
    );
    addTearDown(container.dispose);
    await container.read(expensesProvider.notifier).fetchExpenses(_userId);
    await container
        .read(receivablesProvider.notifier)
        .fetchReceivables(_userId);
    await container.read(payablesProvider.notifier).fetchPayables(_userId);
    await container.read(settingsProvider.notifier).loadSettings();
    container.read(pendingTransactionsProvider.notifier).refresh();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          builder: (context, child) =>
              AmbientBackground(child: child ?? const SizedBox()),
          home: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(settle);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('login', (t) => shoot(t, 'mobile_login', const LoginScreen()));
  testWidgets(
    'dashboard',
    (t) => shoot(t, 'mobile_dashboard', const DashboardScreen()),
  );
  testWidgets(
    'expenses',
    (t) => shoot(t, 'mobile_expenses', const ExpensesScreen()),
  );
  testWidgets(
    'insights',
    (t) => shoot(t, 'mobile_insights', const AnalyticsScreen()),
  );
  testWidgets('debts', (t) => shoot(t, 'mobile_debts', const DebtsScreen()));
  testWidgets(
    'person ledger',
    (t) => shoot(t, 'mobile_ledger', const PersonLedgerScreen(person: 'Rahul')),
  );
  testWidgets(
    'settings',
    (t) => shoot(t, 'mobile_settings', const SettingsScreen()),
  );
  testWidgets(
    'add expense sheet',
    (t) => shoot(
      t,
      'mobile_add_expense',
      const Scaffold(
        backgroundColor: Color(0xFF131318),
        body: SafeArea(child: AddExpenseForm(isDialog: false)),
      ),
    ),
  );

  // The shell carries the labeled sidebar (>=1280) and the icon rail below.
  testWidgets(
    'desktop shell',
    (t) => shoot(t, 'desktop_shell', const AppShell(), size: _desktop),
  );
  testWidgets(
    'tablet shell (icon rail)',
    (t) =>
        shoot(t, 'tablet_shell', const AppShell(), size: const Size(1100, 800)),
  );
  testWidgets(
    'mobile shell (bottom nav)',
    (t) => shoot(t, 'mobile_shell', const AppShell()),
  );
  // The bottom bar has to survive the narrowest phone still shipping, a
  // large phone, and a user running big system fonts — no wrapped labels,
  // no clipping, no collision with the centre button.
  testWidgets(
    'nav on a 320dp phone',
    (t) => shoot(t, 'nav_320', const AppShell(), size: const Size(320, 568)),
  );
  testWidgets(
    'nav on a 430dp phone',
    (t) => shoot(t, 'nav_430', const AppShell(), size: const Size(430, 932)),
  );
  testWidgets(
    'nav at 130% system font',
    (t) => shoot(
      t,
      'nav_large_text',
      const AppShell(),
      size: const Size(360, 800),
      textScale: 1.3,
    ),
  );
  testWidgets(
    'desktop dashboard',
    (t) =>
        shoot(t, 'desktop_dashboard', const DashboardScreen(), size: _desktop),
  );
  testWidgets(
    'desktop expenses',
    (t) => shoot(t, 'desktop_expenses', const ExpensesScreen(), size: _desktop),
  );
  testWidgets(
    'desktop debts',
    (t) => shoot(t, 'desktop_debts', const DebtsScreen(), size: _desktop),
  );
  testWidgets(
    'desktop insights',
    (t) =>
        shoot(t, 'desktop_insights', const AnalyticsScreen(), size: _desktop),
  );
}
