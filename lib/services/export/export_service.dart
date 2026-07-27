import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/expense/expense_model.dart';
import '../../models/payable/payable_model.dart';
import '../../models/receivable/receivable_model.dart';
import '../../models/recurring/recurring_expense_template.dart';
import '../../utils/formatters/formatters.dart';
import 'csv_encoder.dart';
import 'export_models.dart';

class ExportDataset {
  final List<Expense> expenses;
  final List<Receivable> receivables;
  final List<Payable> payables;
  final List<RecurringExpenseTemplate> recurringTemplates;
  final ExportBudgetSnapshot budget;

  const ExportDataset({
    required this.expenses,
    required this.receivables,
    required this.payables,
    required this.recurringTemplates,
    required this.budget,
  });
}

class ExportBudgetSnapshot {
  final double budget;
  final double spent;

  const ExportBudgetSnapshot({required this.budget, required this.spent});

  double get remaining => budget > 0 ? (budget - spent) : 0.0;
  double get percentSpent => budget > 0 ? (spent / budget) : 0.0;
  bool get hasBudget => budget > 0;
}

class ExportAnalyticsSummary {
  final double totalSpent;
  final int transactionCount;
  final Map<String, double> categoryTotals;

  const ExportAnalyticsSummary({
    required this.totalSpent,
    required this.transactionCount,
    required this.categoryTotals,
  });
}

class ExportService {
  static const String inrSymbol = '₹';

  const ExportService();

  ExportAnalyticsSummary buildAnalyticsSummary(List<Expense> expenses) {
    final total = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final categoryTotals = <String, double>{};
    for (final e in expenses) {
      categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amount;
    }
    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ExportAnalyticsSummary(
      totalSpent: total,
      transactionCount: expenses.length,
      categoryTotals: {for (final e in sorted) e.key: e.value},
    );
  }

  ExportGeneratedFile generateCsv({
    required ExportDataset dataset,
    required bool includeAnalyticsSummary,
    required bool darkTheme,
    required String fileNameBase,
  }) {
    final encoder = CsvEncoder();
    final summary = buildAnalyticsSummary(dataset.expenses);

    final lines = <String>[];
    lines.add('EXPENSES');
    lines.add(
      encoder.encodeRow([
        'id',
        'date',
        'category',
        'amount',
        'amount_inr',
        'description',
        'recurring_template_id',
        'recurring_due_date',
      ]),
    );
    for (final e in dataset.expenses) {
      lines.add(
        encoder.encodeRow([
          e.id,
          e.date.toIso8601String(),
          e.category,
          e.amount.toStringAsFixed(2),
          AppFormatters.formatCurrency(e.amount, symbol: inrSymbol),
          e.description ?? '',
          e.recurringTemplateId ?? '',
          e.recurringDueDate?.toIso8601String() ?? '',
        ]),
      );
    }

    lines.add('');
    lines.add('RECEIVABLES');
    lines.add(
      encoder.encodeRow([
        'id',
        'due_date',
        'from_person',
        'amount',
        'amount_inr',
        'is_paid',
        'description',
      ]),
    );
    for (final r in dataset.receivables) {
      lines.add(
        encoder.encodeRow([
          r.id,
          r.dueDate.toIso8601String(),
          r.fromPerson,
          r.amount.toStringAsFixed(2),
          AppFormatters.formatCurrency(r.amount, symbol: inrSymbol),
          r.isPaid ? 'paid' : 'unpaid',
          r.description ?? '',
        ]),
      );
    }

    lines.add('');
    lines.add('PAYABLES');
    lines.add(
      encoder.encodeRow([
        'id',
        'due_date',
        'to_person',
        'category',
        'amount',
        'remaining_amount',
        'status',
        'notes',
      ]),
    );
    for (final p in dataset.payables) {
      lines.add(
        encoder.encodeRow([
          p.id,
          p.dueDate.toIso8601String(),
          p.toPerson,
          p.category,
          p.amount.toStringAsFixed(2),
          p.remainingAmount.toStringAsFixed(2),
          _payableStatusLabel(p),
          p.notes ?? '',
        ]),
      );
    }

    lines.add('');
    lines.add('PAYABLE_SETTLEMENTS');
    lines.add(
      encoder.encodeRow([
        'payable_id',
        'settled_at',
        'amount',
        'remaining_after',
        'note',
      ]),
    );
    for (final p in dataset.payables) {
      for (final entry in p.settlements) {
        lines.add(
          encoder.encodeRow([
            p.id,
            entry.settledAt.toIso8601String(),
            entry.amount.toStringAsFixed(2),
            entry.remainingAfter.toStringAsFixed(2),
            entry.note ?? '',
          ]),
        );
      }
    }

    lines.add('');
    lines.add('RECURRING_TEMPLATES');
    lines.add(
      encoder.encodeRow([
        'id',
        'next_due_date',
        'category',
        'amount',
        'amount_inr',
        'frequency',
        'payment_method',
        'is_active',
        'notes',
      ]),
    );
    for (final t in dataset.recurringTemplates) {
      lines.add(
        encoder.encodeRow([
          t.id,
          t.nextDueDate.toIso8601String(),
          t.category,
          t.amount.toStringAsFixed(2),
          AppFormatters.formatCurrency(t.amount, symbol: inrSymbol),
          t.frequency.name,
          t.paymentMethod,
          t.isActive ? 'active' : 'inactive',
          t.notes ?? '',
        ]),
      );
    }

    if (includeAnalyticsSummary) {
      lines.add('');
      lines.add('ANALYTICS_SUMMARY');
      lines.add(encoder.encodeRow(['transactions', summary.transactionCount]));
      lines.add(
        encoder.encodeRow([
          'total_spent',
          summary.totalSpent.toStringAsFixed(2),
        ]),
      );
      lines.add(
        encoder.encodeRow([
          'total_spent_inr',
          AppFormatters.formatCurrency(summary.totalSpent, symbol: inrSymbol),
        ]),
      );
      lines.add('');
      lines.add('CATEGORY_BREAKDOWN');
      lines.add(encoder.encodeRow(['category', 'amount', 'amount_inr']));
      for (final entry in summary.categoryTotals.entries) {
        lines.add(
          encoder.encodeRow([
            entry.key,
            entry.value.toStringAsFixed(2),
            AppFormatters.formatCurrency(entry.value, symbol: inrSymbol),
          ]),
        );
      }
    }

    final csv = lines.join(const CsvEncoder().lineTerminator);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final preview = csv.length > 2500 ? csv.substring(0, 2500) : csv;
    return ExportGeneratedFile(
      fileName: '$fileNameBase.csv',
      mimeType: 'text/csv',
      bytes: bytes,
      previewText: preview,
    );
  }

  ExportGeneratedFile generateExcel({
    required ExportDataset dataset,
    required bool includeAnalyticsSummary,
    required bool darkTheme,
    required String fileNameBase,
  }) {
    final excel = xls.Excel.createExcel();
    excel.delete('Sheet1');

    _addExpensesSheet(excel, dataset.expenses);
    _addReceivablesSheet(excel, dataset.receivables);
    _addPayablesSheet(excel, dataset.payables);
    _addPayableSettlementsSheet(excel, dataset.payables);
    _addRecurringSheet(excel, dataset.recurringTemplates);
    if (includeAnalyticsSummary) {
      final summary = buildAnalyticsSummary(dataset.expenses);
      _addAnalyticsSheet(excel, summary);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('Failed to encode Excel workbook');
    }
    return ExportGeneratedFile(
      fileName: '$fileNameBase.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: Uint8List.fromList(bytes),
      previewText:
          'Excel workbook generated (${dataset.expenses.length} expenses, '
          '${dataset.receivables.length} receivables, '
          '${dataset.payables.length} payables, '
          '${dataset.recurringTemplates.length} recurring templates).',
    );
  }

  Future<ExportGeneratedFile> generatePdf({
    required ExportDataset dataset,
    required bool includeAnalyticsSummary,
    required bool darkTheme,
    required String title,
    required String fileNameBase,
  }) async {
    final doc = pw.Document(title: title);
    final summary = buildAnalyticsSummary(dataset.expenses);

    final palette = _pdfPalette(darkTheme: darkTheme);

    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            _pdfHeader(title: title, palette: palette),
            pw.SizedBox(height: 14),
            _pdfSummaryRow(summary: summary, palette: palette),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Budget insight (current month)', palette),
            pw.SizedBox(height: 8),
            _pdfBudgetCard(dataset.budget, palette),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Receivables summary', palette),
            pw.SizedBox(height: 8),
            _pdfReceivablesSummary(dataset.receivables, palette),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Payables summary', palette),
            pw.SizedBox(height: 8),
            _pdfPayablesSummary(dataset.payables, palette),
            pw.SizedBox(height: 18),
            if (includeAnalyticsSummary) ...[
              _pdfSectionTitle('Category breakdown', palette),
              pw.SizedBox(height: 8),
              _pdfCategoryBreakdown(summary, palette),
              pw.SizedBox(height: 18),
            ],
            _pdfSectionTitle('Transactions', palette),
            pw.SizedBox(height: 8),
            _pdfExpensesTable(dataset.expenses, palette),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Receivables', palette),
            pw.SizedBox(height: 8),
            _pdfReceivablesTable(dataset.receivables, palette),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Payables', palette),
            pw.SizedBox(height: 8),
            _pdfPayablesTable(dataset.payables, palette),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Recurring templates', palette),
            pw.SizedBox(height: 8),
            _pdfRecurringTable(dataset.recurringTemplates, palette),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    return ExportGeneratedFile(
      fileName: '$fileNameBase.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList(bytes),
      previewText:
          'PDF report generated (${dataset.expenses.length} expenses).',
    );
  }

  pw.Widget _pdfBudgetCard(ExportBudgetSnapshot budget, _PdfPalette palette) {
    final budgetText = budget.hasBudget
        ? AppFormatters.formatCurrency(budget.budget, symbol: inrSymbol)
        : 'Not set';
    final spentText = AppFormatters.formatCurrency(
      budget.spent,
      symbol: inrSymbol,
    );
    final remainingText = budget.hasBudget
        ? AppFormatters.formatCurrency(budget.remaining, symbol: inrSymbol)
        : '—';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: palette.surface,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Budget',
              value: budgetText,
              palette: palette,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Spent',
              value: spentText,
              palette: palette,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Remaining',
              value: remainingText,
              palette: palette,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfMiniMetric({
    required String label,
    required String value,
    required _PdfPalette palette,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(color: palette.mutedText, fontSize: 9),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: palette.text,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfReceivablesSummary(
    List<Receivable> receivables,
    _PdfPalette palette,
  ) {
    final unpaid = receivables.where((r) => !r.isPaid).toList();
    final unpaidTotal = unpaid.fold(0.0, (s, r) => s + r.amount);
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: palette.surface,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Unpaid count',
              value: unpaid.length.toString(),
              palette: palette,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Unpaid total',
              value: AppFormatters.formatCurrency(
                unpaidTotal,
                symbol: inrSymbol,
              ),
              palette: palette,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfPayablesSummary(List<Payable> payables, _PdfPalette palette) {
    final outstanding = payables.where((p) => p.remainingAmount > 0).toList();
    final outstandingTotal = outstanding.fold(
      0.0,
      (s, p) => s + p.remainingAmount,
    );
    final overdue = outstanding.where(_isPayableOverdue).toList();
    final overdueTotal = overdue.fold(0.0, (s, p) => s + p.remainingAmount);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: palette.surface,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Outstanding',
              value: outstanding.length.toString(),
              palette: palette,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Outstanding total',
              value: AppFormatters.formatCurrency(
                outstandingTotal,
                symbol: inrSymbol,
              ),
              palette: palette,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _pdfMiniMetric(
              label: 'Overdue total',
              value: AppFormatters.formatCurrency(
                overdueTotal,
                symbol: inrSymbol,
              ),
              palette: palette,
            ),
          ),
        ],
      ),
    );
  }

  void _addExpensesSheet(xls.Excel excel, List<Expense> expenses) {
    final sheet = excel['Expenses'];
    final headerStyle = _headerStyle();
    final headers = [
      'ID',
      'Date',
      'Category',
      'Amount',
      'Amount (INR)',
      'Description',
      'Recurring Template ID',
      'Recurring Due Date',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = xls.TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }
    var row = 1;
    for (final e in expenses) {
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xls.TextCellValue(
        e.id,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = xls.TextCellValue(
        e.date.toIso8601String(),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = xls.TextCellValue(
        e.category,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = xls.DoubleCellValue(
        e.amount,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = xls.TextCellValue(
        AppFormatters.formatCurrency(e.amount, symbol: inrSymbol),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = xls.TextCellValue(
        e.description ?? '',
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = xls.TextCellValue(
        e.recurringTemplateId ?? '',
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          .value = xls.TextCellValue(
        e.recurringDueDate?.toIso8601String() ?? '',
      );
      row++;
    }

    sheet.appendRow([
      xls.TextCellValue('TOTAL'),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.DoubleCellValue(expenses.fold(0.0, (s, e) => s + e.amount)),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
    ]);
  }

  void _addReceivablesSheet(xls.Excel excel, List<Receivable> receivables) {
    final sheet = excel['Receivables'];
    final headerStyle = _headerStyle();
    final headers = [
      'ID',
      'Due Date',
      'From',
      'Amount',
      'Amount (INR)',
      'Status',
      'Description',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = xls.TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }
    var row = 1;
    for (final r in receivables) {
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xls.TextCellValue(
        r.id,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = xls.TextCellValue(
        r.dueDate.toIso8601String(),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = xls.TextCellValue(
        r.fromPerson,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = xls.DoubleCellValue(
        r.amount,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = xls.TextCellValue(
        AppFormatters.formatCurrency(r.amount, symbol: inrSymbol),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = xls.TextCellValue(
        r.isPaid ? 'Paid' : 'Unpaid',
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = xls.TextCellValue(
        r.description ?? '',
      );
      row++;
    }

    sheet.appendRow([
      xls.TextCellValue('TOTAL (UNPAID)'),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.DoubleCellValue(
        receivables.where((r) => !r.isPaid).fold(0.0, (s, r) => s + r.amount),
      ),
    ]);
  }

  void _addPayablesSheet(xls.Excel excel, List<Payable> payables) {
    final sheet = excel['Payables'];
    final headerStyle = _headerStyle();
    final headers = [
      'ID',
      'Due Date',
      'To',
      'Category',
      'Amount',
      'Remaining',
      'Status',
      'Notes',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = xls.TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }
    var row = 1;
    for (final p in payables) {
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xls.TextCellValue(
        p.id,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = xls.TextCellValue(
        p.dueDate.toIso8601String(),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = xls.TextCellValue(
        p.toPerson,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = xls.TextCellValue(
        p.category,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = xls.DoubleCellValue(
        p.amount,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = xls.DoubleCellValue(
        p.remainingAmount,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = xls.TextCellValue(
        _payableStatusLabel(p),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          .value = xls.TextCellValue(
        p.notes ?? '',
      );
      row++;
    }

    sheet.appendRow([
      xls.TextCellValue('TOTAL (OUTSTANDING)'),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.DoubleCellValue(payables.fold(0.0, (s, p) => s + p.amount)),
      xls.DoubleCellValue(payables.fold(0.0, (s, p) => s + p.remainingAmount)),
    ]);
  }

  void _addPayableSettlementsSheet(xls.Excel excel, List<Payable> payables) {
    final sheet = excel['Payable Settlements'];
    final headerStyle = _headerStyle();
    final headers = [
      'Payable ID',
      'Settled At',
      'Amount',
      'Remaining After',
      'Note',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = xls.TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    var row = 1;
    for (final p in payables) {
      for (final entry in p.settlements) {
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = xls.TextCellValue(
          p.id,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = xls.TextCellValue(
          entry.settledAt.toIso8601String(),
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = xls.DoubleCellValue(
          entry.amount,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = xls.DoubleCellValue(
          entry.remainingAfter,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
            .value = xls.TextCellValue(
          entry.note ?? '',
        );
        row++;
      }
    }
  }

  void _addRecurringSheet(
    xls.Excel excel,
    List<RecurringExpenseTemplate> templates,
  ) {
    final sheet = excel['Recurring'];
    final headerStyle = _headerStyle();
    final headers = [
      'ID',
      'Next Due Date',
      'Category',
      'Amount',
      'Amount (INR)',
      'Frequency',
      'Payment Method',
      'Active',
      'Notes',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = xls.TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }
    var row = 1;
    for (final t in templates) {
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xls.TextCellValue(
        t.id,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = xls.TextCellValue(
        t.nextDueDate.toIso8601String(),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = xls.TextCellValue(
        t.category,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = xls.DoubleCellValue(
        t.amount,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = xls.TextCellValue(
        AppFormatters.formatCurrency(t.amount, symbol: inrSymbol),
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = xls.TextCellValue(
        t.frequency.name,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = xls.TextCellValue(
        t.paymentMethod,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          .value = xls.TextCellValue(
        t.isActive ? 'Yes' : 'No',
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
          .value = xls.TextCellValue(
        t.notes ?? '',
      );
      row++;
    }
  }

  void _addAnalyticsSheet(xls.Excel excel, ExportAnalyticsSummary summary) {
    final sheet = excel['Analytics'];
    final headerStyle = _headerStyle();
    var row = 0;
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = xls.TextCellValue(
      'Metric',
    );
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = xls.TextCellValue(
      'Value',
    );
    sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        headerStyle;
    sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .cellStyle =
        headerStyle;
    row++;

    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = xls.TextCellValue(
      'Transactions',
    );
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = xls.IntCellValue(
      summary.transactionCount,
    );
    row++;

    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = xls.TextCellValue(
      'Total spent',
    );
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = xls.DoubleCellValue(
      summary.totalSpent,
    );
    row++;

    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = xls.TextCellValue(
      'Total spent (INR)',
    );
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = xls.TextCellValue(
      AppFormatters.formatCurrency(summary.totalSpent, symbol: inrSymbol),
    );
    row += 2;

    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = xls.TextCellValue(
      'Category',
    );
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = xls.TextCellValue(
      'Amount',
    );
    sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        headerStyle;
    sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .cellStyle =
        headerStyle;
    row++;

    for (final entry in summary.categoryTotals.entries) {
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xls.TextCellValue(
        entry.key,
      );
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = xls.DoubleCellValue(
        entry.value,
      );
      row++;
    }
  }

  xls.CellStyle _headerStyle() {
    return xls.CellStyle(
      bold: true,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
    );
  }

  _PdfPalette _pdfPalette({required bool darkTheme}) {
    if (darkTheme) {
      return _PdfPalette(
        surface: PdfColor.fromInt(0xFF161B24),
        text: PdfColors.white,
        mutedText: PdfColor.fromInt(0xFFB8C1D1),
        accent: PdfColor.fromInt(0xFF6AE4FF),
        border: PdfColor.fromInt(0xFF2A3140),
      );
    }
    return _PdfPalette(
      surface: PdfColor.fromInt(0xFFF3F5F8),
      text: PdfColor.fromInt(0xFF111827),
      mutedText: PdfColor.fromInt(0xFF6B7280),
      accent: PdfColor.fromInt(0xFF0066FF),
      border: PdfColor.fromInt(0xFFE5E7EB),
    );
  }

  pw.Widget _pdfHeader({required String title, required _PdfPalette palette}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: palette.surface,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 36,
            height: 36,
            decoration: pw.BoxDecoration(
              color: palette.accent,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Center(
              child: pw.Text(
                '₹',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 18,
                  color: PdfColors.black,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Generated on ${AppFormatters.formatDate(DateTime.now())}',
                  style: pw.TextStyle(color: palette.mutedText, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String text, _PdfPalette palette) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: palette.text,
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  pw.Widget _pdfSummaryRow({
    required ExportAnalyticsSummary summary,
    required _PdfPalette palette,
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _pdfMetricCard(
            label: 'Transactions',
            value: summary.transactionCount.toString(),
            palette: palette,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _pdfMetricCard(
            label: 'Total spent',
            value: AppFormatters.formatCurrency(
              summary.totalSpent,
              symbol: inrSymbol,
            ),
            palette: palette,
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfMetricCard({
    required String label,
    required String value,
    required _PdfPalette palette,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: palette.surface,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(color: palette.mutedText, fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: palette.text,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCategoryBreakdown(
    ExportAnalyticsSummary summary,
    _PdfPalette palette,
  ) {
    final rows = summary.categoryTotals.entries
        .take(12)
        .map(
          (e) => [
            e.key,
            AppFormatters.formatCurrency(e.value, symbol: inrSymbol),
          ],
        )
        .toList();
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(
        color: palette.text,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: pw.BoxDecoration(color: palette.surface),
      cellStyle: pw.TextStyle(color: palette.text, fontSize: 10),
      border: pw.TableBorder.all(color: palette.border),
      headers: const ['Category', 'Amount'],
      data: rows,
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  pw.Widget _pdfExpensesTable(List<Expense> expenses, _PdfPalette palette) {
    final rows = expenses
        .take(120)
        .map(
          (e) => [
            AppFormatters.formatDate(e.date),
            e.category,
            AppFormatters.formatCurrency(e.amount, symbol: inrSymbol),
            (e.description ?? '').trim(),
          ],
        )
        .toList();
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(
        color: palette.text,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: pw.BoxDecoration(color: palette.surface),
      cellStyle: pw.TextStyle(color: palette.text, fontSize: 9),
      border: pw.TableBorder.all(color: palette.border),
      headers: const ['Date', 'Category', 'Amount', 'Notes'],
      data: rows,
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.2),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.0),
        3: const pw.FlexColumnWidth(2.6),
      },
    );
  }

  pw.Widget _pdfReceivablesTable(
    List<Receivable> receivables,
    _PdfPalette palette,
  ) {
    final rows = receivables
        .take(120)
        .map(
          (r) => [
            AppFormatters.formatDate(r.dueDate),
            r.fromPerson,
            AppFormatters.formatCurrency(r.amount, symbol: inrSymbol),
            r.isPaid ? 'Paid' : 'Unpaid',
          ],
        )
        .toList();
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(
        color: palette.text,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: pw.BoxDecoration(color: palette.surface),
      cellStyle: pw.TextStyle(color: palette.text, fontSize: 9),
      border: pw.TableBorder.all(color: palette.border),
      headers: const ['Due', 'From', 'Amount', 'Status'],
      data: rows,
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  pw.Widget _pdfPayablesTable(List<Payable> payables, _PdfPalette palette) {
    final rows = payables
        .take(120)
        .map(
          (p) => [
            AppFormatters.formatDate(p.dueDate),
            p.toPerson,
            AppFormatters.formatCurrency(p.remainingAmount, symbol: inrSymbol),
            _payableStatusLabel(p),
          ],
        )
        .toList();
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(
        color: palette.text,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: pw.BoxDecoration(color: palette.surface),
      cellStyle: pw.TextStyle(color: palette.text, fontSize: 9),
      border: pw.TableBorder.all(color: palette.border),
      headers: const ['Due', 'To', 'Remaining', 'Status'],
      data: rows,
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  pw.Widget _pdfRecurringTable(
    List<RecurringExpenseTemplate> templates,
    _PdfPalette palette,
  ) {
    final rows = templates
        .take(120)
        .map(
          (t) => [
            AppFormatters.formatDate(t.nextDueDate),
            t.category,
            AppFormatters.formatCurrency(t.amount, symbol: inrSymbol),
            t.frequency.name,
            t.isActive ? 'Active' : 'Inactive',
          ],
        )
        .toList();
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(
        color: palette.text,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: pw.BoxDecoration(color: palette.surface),
      cellStyle: pw.TextStyle(color: palette.text, fontSize: 9),
      border: pw.TableBorder.all(color: palette.border),
      headers: const ['Next due', 'Category', 'Amount', 'Frequency', 'State'],
      data: rows,
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.2),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.0),
        3: const pw.FlexColumnWidth(1.0),
        4: const pw.FlexColumnWidth(1.0),
      },
    );
  }

  bool _isPayableOverdue(Payable payable) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final due = DateTime(
      payable.dueDate.year,
      payable.dueDate.month,
      payable.dueDate.day,
    );
    return due.isBefore(todayOnly) && payable.remainingAmount > 0;
  }

  String _payableStatusLabel(Payable payable) {
    if (payable.remainingAmount <= 0 || payable.status == PayableStatus.paid) {
      return 'Paid';
    }
    if (_isPayableOverdue(payable)) {
      return 'Overdue';
    }
    if (payable.status == PayableStatus.partial) {
      return 'Partial';
    }
    return 'Pending';
  }
}

class _PdfPalette {
  final PdfColor surface;
  final PdfColor text;
  final PdfColor mutedText;
  final PdfColor accent;
  final PdfColor border;

  _PdfPalette({
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.border,
  });
}
