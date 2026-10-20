import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/party_repository.dart';
import '../database/app_database.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/period.dart';
import 'app_scaffold.dart';
import 'buttons.dart';
import 'inputs.dart';

/// Result of the customer picker: a party, or "Cash Sale" (walk-in).
sealed class PartyChoice {
  const PartyChoice();
}

class WalkIn extends PartyChoice {
  const WalkIn();
}

class PickedParty extends PartyChoice {
  const PickedParty(this.party);
  final Party party;
}

/// Pick or create a customer. Returns null when dismissed.
Future<PartyChoice?> showPartyPicker(BuildContext context, {bool allowWalkIn = true}) {
  return showModalBottomSheet<PartyChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PartyPicker(allowWalkIn: allowWalkIn),
  );
}

final _partySearchProvider = StreamProvider.autoDispose.family<List<Party>, String>(
  (ref, query) => ref.watch(partyRepositoryProvider).watchParties(query: query, type: 'customer'),
);

class _PartyPicker extends ConsumerStatefulWidget {
  const _PartyPicker({required this.allowWalkIn});
  final bool allowWalkIn;

  @override
  ConsumerState<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends ConsumerState<_PartyPicker> {
  String _query = '';
  bool _creating = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final party = await ref.read(partyRepositoryProvider).create(name: _name.text, phone: _phone.text);
    if (mounted) Navigator.pop(context, PickedParty(party));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    if (_creating) {
      return Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, bottomInset + AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New customer', style: text.titleMedium),
            const SizedBox(height: AppSpace.lg),
            LabeledField(
              label: 'Name',
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpace.md),
            LabeledField(label: 'Phone (optional)', controller: _phone, keyboardType: TextInputType.phone),
            const SizedBox(height: AppSpace.xl),
            FormActions(
              primaryLabel: 'Save customer',
              busy: _saving,
              onPrimary: _create,
              onSecondary: () => setState(() => _creating = false),
            ),
          ],
        ),
      );
    }

    final parties = ref.watch(_partySearchProvider(_query));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, bottomInset),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('Choose customer', style: text.titleMedium)),
                GhostAddButton(label: 'New', onPressed: () => setState(() => _creating = true)),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            SearchField(hint: 'Search name or phone…', onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: AppSpace.sm),
            if (widget.allowWalkIn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: c.surfaceTint, child: Icon(Icons.storefront, color: c.primary)),
                title: Text('Cash Sale', style: text.bodyLarge),
                subtitle: Text('Walk-in customer', style: text.labelSmall),
                onTap: () => Navigator.pop(context, const WalkIn()),
              ),
            Expanded(
              child: parties.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('$e'),
                data: (list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.person_outline,
                        title: _query.isEmpty ? 'No customers yet' : 'No matches',
                        action: GhostAddButton(
                          label: 'Add customer',
                          onPressed: () => setState(() {
                            _creating = true;
                            _name.text = _query;
                          }),
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: c.tintFor(list[i].id),
                            child: Text(
                              list[i].name.characters.first.toUpperCase(),
                              style: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
                            ),
                          ),
                          title: Text(list[i].name, style: text.bodyLarge),
                          subtitle: list[i].phone.isEmpty ? null : Text(list[i].phone, style: text.labelSmall),
                          onTap: () => Navigator.pop(context, PickedParty(list[i])),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String periodLabel(Period p, AppFormats f) => switch (p.kind) {
      PeriodKind.today => 'Today',
      PeriodKind.yesterday => 'Yesterday',
      PeriodKind.thisWeek => 'This Week',
      PeriodKind.thisMonth => 'This Month',
      PeriodKind.allTime => 'All Time',
      PeriodKind.custom =>
        '${f.date.format(p.start!)} – ${f.date.format(p.end!.subtract(const Duration(days: 1)))}',
    };

/// Today / Yesterday / This Week / This Month / Custom / All Time.
Future<Period?> showPeriodPicker(BuildContext context, Period current) {
  return showModalBottomSheet<Period>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      Widget option(PeriodKind kind, String label) => ListTile(
            title: Text(label, style: text.bodyLarge),
            trailing: current.kind == kind ? Icon(Icons.check, color: sheetContext.colors.primary) : null,
            onTap: () async {
              if (kind == PeriodKind.custom) {
                final now = DateTime.now();
                final range = await showDateRangePicker(
                  context: sheetContext,
                  firstDate: DateTime(2015),
                  lastDate: DateTime(now.year + 1),
                  initialDateRange: current.kind == PeriodKind.custom
                      ? DateTimeRange(start: current.start!, end: current.end!.subtract(const Duration(days: 1)))
                      : null,
                );
                if (range != null && sheetContext.mounted) {
                  Navigator.pop(sheetContext, Period.of(PeriodKind.custom, custom: range));
                }
              } else {
                Navigator.pop(sheetContext, Period.of(kind));
              }
            },
          );
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(PeriodKind.today, 'Today'),
            option(PeriodKind.yesterday, 'Yesterday'),
            option(PeriodKind.thisWeek, 'This Week'),
            option(PeriodKind.thisMonth, 'This Month'),
            option(PeriodKind.custom, 'Custom range…'),
            option(PeriodKind.allTime, 'All Time'),
            const SizedBox(height: AppSpace.lg),
          ],
        ),
      );
    },
  );
}

/// Simple single-choice sheet used by settings.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<({T value, String label})> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.sm),
            child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final o in options)
            ListTile(
              title: Text(o.label, style: Theme.of(ctx).textTheme.bodyLarge),
              trailing: o.value == selected ? Icon(Icons.check, color: ctx.colors.primary) : null,
              onTap: () => Navigator.pop(ctx, o.value),
            ),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
    ),
  );
}
