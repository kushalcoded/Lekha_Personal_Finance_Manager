import '../../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/people/people_providers.dart';
import '../../../theme/app_theme.dart';
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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

  /// Pin someone to the front of the suggestions, or stop offering them.
  /// Hiding is undoable from Settings → People, which the sheet says so nobody
  /// thinks they've deleted a person's history.
  Future<void> _openPersonMenu(String name, bool isPinned) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              ),
              title: Text(isPinned ? 'Unpin $name' : 'Pin $name to the front'),
              onTap: () => Navigator.of(sheetContext).pop('pin'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_rounded),
              title: Text('Hide $name'),
              subtitle: const Text('Undo in Settings → People'),
              onTap: () => Navigator.of(sheetContext).pop('hide'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final notifier = ref.read(peoplePrefsProvider.notifier);
    if (action == 'pin') {
      await notifier.togglePin(name);
    } else {
      await notifier.toggleHide(name);
    }
  }

  Map<String, double> get _exactAmounts => {
    for (final e in _exactControllers.entries)
      e.key: parseAmountExpression(e.value.text.trim()) ?? 0,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final prefs = ref.watch(peoplePrefsProvider);
    final known = ref
        .watch(knownPeopleProvider)
        .where((n) => !_people.any((p) => p.toLowerCase() == n.toLowerCase()))
        .take(8)
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
          Text(
            'Split ${AppFormatters.formatCurrency(widget.total)}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 18),

          const FieldLabel('With'),
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
                    (n) => GestureDetector(
                      // Long-press rather than a visible control: the pills are
                      // a fast path, and hanging an X off each one would make
                      // the row read as a list to manage instead of tap.
                      onLongPress: () => _openPersonMenu(n, prefs.isPinned(n)),
                      child: ChoicePill(
                        label: n,
                        icon: prefs.isPinned(n)
                            ? Icons.push_pin_rounded
                            : Icons.add_rounded,
                        selected: false,
                        onTap: () => _addPerson(n),
                      ),
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
            // Mockup: Equal / Exact as a segmented control.
            _Segmented(
              exact: _mode == SplitMode.exact,
              onChanged: (exact) => setState(
                () => _mode = exact ? SplitMode.exact : SplitMode.equal,
              ),
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
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
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

/// Mockup's Equal / Exact segmented control: dark track, violet active pill.
class _Segmented extends StatelessWidget {
  final bool exact;
  final ValueChanged<bool> onChanged;

  const _Segmented({required this.exact, required this.onChanged});

  Widget _seg(BuildContext context, String label, bool on, VoidCallback tap) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w600,
              color: on ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A21),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _seg(context, 'Equal', !exact, () => onChanged(false)),
          _seg(context, 'Exact', exact, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// Live preview of who ends up owing what — mockup share rows (avatar, name,
/// 'will owe you') plus the outcome stated in words before Done.
class _Preview extends StatelessWidget {
  final SplitResult result;
  final String? paidBy;

  const _Preview({required this.result, required this.paidBy});

  Widget _row(
    BuildContext context,
    String name,
    double amount, {
    String? caption,
    Color? captionColor,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A21),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFF131318),
            child: Text(
              name == 'You' ? 'Y' : name[0].toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: captionColor ?? cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            AppFormatters.formatCurrency(amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);

    final outcome = paidBy == null
        ? 'Your expense records ${AppFormatters.formatCurrency(result.myShare)}'
              ' · ${AppFormatters.formatCurrency(result.othersTotal)} to receivables'
        : 'Your expense records ${AppFormatters.formatCurrency(result.myShare)}'
              ' · you will owe $paidBy';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          context,
          'You',
          result.myShare,
          caption: paidBy != null ? 'you will owe $paidBy' : null,
          captionColor: paidBy != null ? cs.error : null,
        ),
        ...result.others.map(
          (s) => _row(
            context,
            s.person,
            s.amount,
            caption: paidBy == null ? 'will owe you' : null,
            captionColor: calm.positive,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          outcome,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
