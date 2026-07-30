import '../../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/people/people_providers.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/form_bits.dart';
import '../utils/split_helpers.dart';

/// Configure how a bill is split. Returns the new [SplitConfig], or a config
/// with no people to mean "not split". Returns null if dismissed unchanged.
Future<SplitConfig?> showSplitSheet(
  BuildContext context, {
  required double total,
  required SplitConfig initial,
}) {
  return showModalBottomSheet<SplitConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: _SplitSheet(total: total, initial: initial),
      ),
    ),
  );
}

class _SplitSheet extends ConsumerStatefulWidget {
  final double total;
  final SplitConfig initial;

  const _SplitSheet({required this.total, required this.initial});

  @override
  ConsumerState<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<_SplitSheet> {
  late List<String> _people;
  late String? _paidBy;
  late SplitMode _mode;
  final _nameController = TextEditingController();
  final Map<String, TextEditingController> _exactControllers = {};

  @override
  void initState() {
    super.initState();
    _people = [...widget.initial.people];
    _paidBy = widget.initial.paidBy;
    _mode = widget.initial.mode;
    for (final p in _people) {
      _exactControllers[p] = TextEditingController(
        text: widget.initial.exact[p]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _exactControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPerson(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    if (_people.any((p) => p.toLowerCase() == name.toLowerCase())) return;
    setState(() {
      _people.add(name);
      _exactControllers[name] = TextEditingController();
      _nameController.clear();
    });
  }

  void _removePerson(String name) {
    setState(() {
      _people.remove(name);
      _exactControllers.remove(name)?.dispose();
      if (_paidBy == name) _paidBy = null; // payer left the split
    });
  }

  Map<String, double> get _exactAmounts => {
    for (final e in _exactControllers.entries)
      e.key: parseAmountExpression(e.value.text.trim()) ?? 0,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final known = ref
        .watch(knownPeopleProvider)
        .where((n) => !_people.any((p) => p.toLowerCase() == n.toLowerCase()))
        .take(6)
        .toList();

    final result = computeSplit(
      total: widget.total,
      people: _people,
      mode: _mode,
      exactAmounts: _exactAmounts,
    );
    final error = _people.isEmpty ? null : validateSplit(widget.total, result);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Split bill',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Text(
                'Total ${AppFormatters.formatCurrency(widget.total)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          const FieldLabel('Split with'),
          const SizedBox(height: 8),
          if (_people.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _people
                  .map(
                    (p) =>
                        _PersonChip(name: p, onRemove: () => _removePerson(p)),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: _addPerson,
            decoration: InputDecoration(
              hintText: 'Add a name',
              prefixIcon: const Icon(Icons.person_add_alt_rounded, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _addPerson(_nameController.text),
              ),
            ),
          ),
          if (known.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: known
                  .map(
                    (n) => ChoicePill(
                      label: n,
                      icon: Icons.add_rounded,
                      selected: false,
                      onTap: () => _addPerson(n),
                    ),
                  )
                  .toList(),
            ),
          ],

          if (_people.isNotEmpty) ...[
            const SizedBox(height: 18),
            const FieldLabel('Paid by'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoicePill(
                  label: 'You',
                  selected: _paidBy == null,
                  onTap: () => setState(() => _paidBy = null),
                ),
                ..._people.map(
                  (p) => ChoicePill(
                    label: p,
                    selected: _paidBy == p,
                    onTap: () => setState(() => _paidBy = p),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            const FieldLabel('Split'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoicePill(
                  label: 'Equally',
                  selected: _mode == SplitMode.equal,
                  onTap: () => setState(() => _mode = SplitMode.equal),
                ),
                ChoicePill(
                  label: 'Exact amounts',
                  selected: _mode == SplitMode.exact,
                  onTap: () => setState(() => _mode = SplitMode.exact),
                ),
              ],
            ),

            if (_mode == SplitMode.exact) ...[
              const SizedBox(height: 12),
              ..._people.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(p, style: theme.textTheme.bodyMedium),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _exactControllers[p],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixText: '₹',
                            isDense: true,
                            hintText: '0',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            _Preview(result: result, paidBy: _paidBy),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
          ],

          const SizedBox(height: 20),
          Row(
            children: [
              if (widget.initial.isActive)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(const SplitConfig()),
                  child: const Text('Remove split'),
                ),
              const Spacer(),
              SizedBox(
                width: 160,
                child: GradientButton(
                  label: 'Done',
                  enabled: _people.isNotEmpty && error == null,
                  onPressed: () => Navigator.of(context).pop(
                    SplitConfig(
                      people: _people,
                      paidBy: _paidBy,
                      mode: _mode,
                      exact: _exactAmounts,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  final String name;
  final VoidCallback onRemove;

  const _PersonChip({required this.name, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 7, 6, 7),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          InkResponse(
            onTap: onRemove,
            radius: 14,
            child: Icon(Icons.close_rounded, size: 14, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

/// Live preview of who ends up owing what.
class _Preview extends StatelessWidget {
  final SplitResult result;
  final String? paidBy;

  const _Preview({required this.result, required this.paidBy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your share ${AppFormatters.formatCurrency(result.myShare)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (paidBy == null)
            Text(
              '${AppFormatters.formatCurrency(result.othersTotal)} goes to receivables:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Text(
              'You owe $paidBy ${AppFormatters.formatCurrency(result.myShare)} — added to payables.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (paidBy == null) ...[
            const SizedBox(height: 6),
            ...result.others.map(
              (s) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${s.person} owes ${AppFormatters.formatCurrency(s.amount)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
