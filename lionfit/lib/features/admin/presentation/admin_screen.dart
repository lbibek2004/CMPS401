import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/equipment_item.dart';
import '../../workout/domain/workout_models.dart';
import '../data/admin_repository.dart';
import '../domain/admin_models.dart';

/// `/admin` - content management for the shared reference data: the Rec
/// Center equipment list and the exercise catalog.
///
/// Reached from the profile menu, on the admin's normal login - there is no
/// separate admin sign-in. Who may *see* this is decided by `profiles.role`
/// (the router sends members away, and this screen checks again); who may
/// *change* anything is decided by the database, whose RLS lets only
/// `is_admin()` write these tables. No user's training data is shown here.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(trainingProfileProvider);
    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const _NotAdmin(),
      data: (p) => p.isAdmin
          ? DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  leading: BackButton(
                    onPressed: () => context.go(Routes.profile),
                  ),
                  title: const Text('Admin tools'),
                  bottom: const TabBar(
                    tabs: [
                      Tab(
                        icon: Icon(Icons.handyman_outlined),
                        text: 'Equipment',
                      ),
                      Tab(
                        icon: Icon(Icons.fitness_center_outlined),
                        text: 'Exercises',
                      ),
                    ],
                  ),
                ),
                body: const TabBarView(
                  children: [_EquipmentTab(), _ExercisesTab()],
                ),
              ),
            )
          : const _NotAdmin(),
    );
  }
}

class _NotAdmin extends StatelessWidget {
  const _NotAdmin();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('Admins only', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Equipment
// ---------------------------------------------------------------------------

enum _EquipmentFilter { all, outOfService, unverified }

String equipmentStatusLabel(EquipmentStatus status) => switch (status) {
  EquipmentStatus.available => 'Available',
  EquipmentStatus.occupied => 'Occupied',
  EquipmentStatus.outOfService => 'Out of service',
  EquipmentStatus.unknown => 'Unknown',
};

class _EquipmentTab extends ConsumerStatefulWidget {
  const _EquipmentTab();

  @override
  ConsumerState<_EquipmentTab> createState() => _EquipmentTabState();
}

class _EquipmentTabState extends ConsumerState<_EquipmentTab> {
  String _query = '';
  _EquipmentFilter _filter = _EquipmentFilter.all;

  @override
  Widget build(BuildContext context) {
    final equipment = ref.watch(equipmentProvider);
    final catalog = ref.watch(exerciseCatalogProvider).value ?? const [];

    int usedBy(String slug) => catalog
        .where((e) => e.isActive && e.requiredEquipment.contains(slug))
        .length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEquipment(context, null, 0),
        icon: const Icon(Icons.add),
        label: const Text('Add equipment'),
      ),
      body: equipment.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _Retry(onRetry: () => ref.invalidate(equipmentProvider)),
        data: (items) {
          final q = _query.trim().toLowerCase();
          final shown = [
            for (final item in items)
              if (item.isInventoryItem &&
                  (q.isEmpty ||
                      item.label.toLowerCase().contains(q) ||
                      item.slug.contains(q)) &&
                  switch (_filter) {
                    _EquipmentFilter.all => true,
                    _EquipmentFilter.outOfService => !item.isUsable,
                    _EquipmentFilter.unverified => !item.isVerified,
                  })
                item,
          ]..sort((a, b) => a.label.compareTo(b.label));
          return _AdminList(
            search: 'Search equipment',
            onSearch: (v) => setState(() => _query = v),
            filters: [
              for (final (f, label) in const [
                (_EquipmentFilter.all, 'All'),
                (_EquipmentFilter.outOfService, 'Not usable'),
                (_EquipmentFilter.unverified, 'Unverified'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
            summary:
                '${shown.length} of '
                '${items.where((i) => i.isInventoryItem).length} items',
            children: [
              for (final item in shown)
                _EquipmentRow(
                  item: item,
                  usedBy: usedBy(item.slug),
                  onTap: () => _openEquipment(context, item, usedBy(item.slug)),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEquipment(
    BuildContext context,
    EquipmentItem? item,
    int usedBy,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EquipmentSheet(item: item, usedBy: usedBy),
    );
    if ((saved ?? false) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(item == null ? 'Equipment added.' : 'Saved.')),
      );
    }
  }
}

class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({
    required this.item,
    required this.usedBy,
    required this.onTap,
  });

  final EquipmentItem item;
  final int usedBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      onTap: onTap,
      title: Text(item.label),
      subtitle: Text(
        [
          'Qty ${item.quantity ?? '?'}',
          '$usedBy ${usedBy == 1 ? 'exercise' : 'exercises'}',
          if (!item.isVerified) 'unverified',
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: _StatusChip(status: item.status, usable: item.isUsable),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.usable});

  final EquipmentStatus status;
  final bool usable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (fill, ink) = switch (status) {
      EquipmentStatus.available when usable => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      EquipmentStatus.occupied => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      EquipmentStatus.outOfService || EquipmentStatus.available => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      EquipmentStatus.unknown => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    final text = status == EquipmentStatus.available && !usable
        ? 'None on floor'
        : equipmentStatusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: ink),
      ),
    );
  }
}

class _EquipmentSheet extends ConsumerStatefulWidget {
  const _EquipmentSheet({required this.item, required this.usedBy});

  /// Null = adding a new item.
  final EquipmentItem? item;
  final int usedBy;

  @override
  ConsumerState<_EquipmentSheet> createState() => _EquipmentSheetState();
}

class _EquipmentSheetState extends ConsumerState<_EquipmentSheet> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.item?.label ?? '');
  late final _slug = TextEditingController(text: widget.item?.slug ?? '');
  late final _quantity = TextEditingController(
    text: widget.item?.quantity?.toString() ?? '',
  );
  late final _notes = TextEditingController(text: widget.item?.notes ?? '');
  late EquipmentStatus _status =
      widget.item?.status ?? EquipmentStatus.available;
  late bool _verified = widget.item?.isVerified ?? true;
  bool _slugEdited = false;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.item == null;

  @override
  void dispose() {
    _label.dispose();
    _slug.dispose();
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    final qtyText = _quantity.text.trim();
    final quantity = qtyText.isEmpty ? null : int.parse(qtyText);
    try {
      if (_isNew) {
        await repo.addEquipment(
          slug: _slug.text.trim(),
          label: _label.text,
          status: _status,
          quantity: quantity,
          isVerified: _verified,
          notes: _notes.text,
        );
      } else {
        await repo.updateEquipment(
          widget.item!.slug,
          label: _label.text,
          status: _status,
          quantity: quantity,
          isVerified: _verified,
          notes: _notes.text,
        );
      }
      refreshReferenceData(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on AdminWriteFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SheetFrame(
      title: _isNew ? 'Add equipment' : widget.item!.label,
      subtitle: _isNew
          ? null
          : 'ID ${widget.item!.slug} · used by ${widget.usedBy} active '
                '${widget.usedBy == 1 ? 'exercise' : 'exercises'}',
      error: _error,
      saving: _saving,
      onSave: _save,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (v) {
                if (_isNew && !_slugEdited) _slug.text = slugify(v);
              },
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Give it a name.' : null,
            ),
            if (_isNew) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _slug,
                decoration: const InputDecoration(
                  labelText: 'ID',
                  helperText:
                      'What exercises refer to. Cannot be changed later.',
                ),
                onChanged: (_) => _slugEdited = true,
                validator: (v) =>
                    kSlugPattern.hasMatch(v?.trim() ?? '') ? null : 'Lowercase letters, digits and _, starting with a letter.',
              ),
            ],
            const SizedBox(height: 20),
            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in EquipmentStatus.values)
                  ChoiceChip(
                    label: Text(equipmentStatusLabel(s)),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Anything but Available takes its exercises out of plans and '
              'swaps until it is back.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantity on the floor',
                helperText: 'Blank if unknown. 0 means none.',
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                return n == null || n > 999 ? 'Enter 0-999' : null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Checked on the floor'),
              value: _verified,
              onChanged: (v) => setState(() => _verified = v),
            ),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Exercises
// ---------------------------------------------------------------------------

class _ExercisesTab extends ConsumerStatefulWidget {
  const _ExercisesTab();

  @override
  ConsumerState<_ExercisesTab> createState() => _ExercisesTabState();
}

class _ExercisesTabState extends ConsumerState<_ExercisesTab> {
  String _query = '';
  bool _showRetired = false;
  final _toggling = <String>{};

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(exerciseCatalogProvider);
    final labels = {
      for (final item in ref.watch(equipmentProvider).value ?? const [])
        item.slug: item.label,
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExercise(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      body: catalog.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _Retry(onRetry: () => ref.invalidate(exerciseCatalogProvider)),
        data: (all) {
          final q = _query.trim().toLowerCase();
          final shown = [
            for (final e in all)
              if ((_showRetired || e.isActive) &&
                  (q.isEmpty || e.name.toLowerCase().contains(q)))
                e,
          ];
          return _AdminList(
            search: 'Search exercises',
            onSearch: (v) => setState(() => _query = v),
            filters: [
              FilterChip(
                label: Text(
                  'Show retired (${all.where((e) => !e.isActive).length})',
                ),
                selected: _showRetired,
                onSelected: (v) => setState(() => _showRetired = v),
              ),
            ],
            summary:
                '${all.where((e) => e.isActive).length} active, '
                '${all.where((e) => !e.isActive).length} retired',
            children: [
              for (final e in shown)
                ListTile(
                  onTap: () => _openExercise(context, e),
                  title: Text(
                    e.name,
                    style: e.isActive
                        ? null
                        : TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            decoration: TextDecoration.lineThrough,
                          ),
                  ),
                  subtitle: Text(
                    [
                      e.primaryMuscleGroups.map(muscleGroupLabel).join(', '),
                      if (e.movementPattern.isNotEmpty)
                        movementPatternLabel(e.movementPattern),
                      e.requiredEquipment.map((s) => labels[s] ?? s).join(', '),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Tooltip(
                    message: e.isActive ? 'Retire' : 'Bring back',
                    child: Switch(
                      value: e.isActive,
                      onChanged: _toggling.contains(e.id)
                          ? null
                          : (v) => _setActive(context, e, v),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setActive(
    BuildContext context,
    CatalogExercise e,
    bool active,
  ) async {
    setState(() => _toggling.add(e.id));
    try {
      await ref.read(adminRepositoryProvider).setExerciseActive(e.id, active);
      refreshReferenceData(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              active
                  ? '${e.name} is back in plans.'
                  : '${e.name} retired. Logged history keeps it.',
            ),
          ),
        );
      }
    } on AdminWriteFailure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(e.id));
    }
  }

  Future<void> _openExercise(BuildContext context, CatalogExercise? e) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: _ExerciseSheet(exercise: e),
      ),
    );
    if ((saved ?? false) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e == null ? 'Exercise added.' : 'Saved.')),
      );
    }
  }
}

class _ExerciseSheet extends ConsumerStatefulWidget {
  const _ExerciseSheet({required this.exercise});

  /// Null = adding a new exercise.
  final CatalogExercise? exercise;

  @override
  ConsumerState<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends ConsumerState<_ExerciseSheet> {
  late final _name = TextEditingController(text: widget.exercise?.name ?? '');
  late final _slug = TextEditingController(text: widget.exercise?.slug ?? '');
  late final _notes = TextEditingController(text: widget.exercise?.notes ?? '');
  late final Set<MuscleGroup> _primary = {
    ...?widget.exercise?.primaryMuscleGroups,
  };
  late final Set<MuscleGroup> _secondary = {
    ...?widget.exercise?.secondaryMuscleGroups,
  };
  late final Set<String> _equipment = {...?widget.exercise?.requiredEquipment};
  late String _pattern = (widget.exercise?.movementPattern.isNotEmpty ?? false)
      ? widget.exercise!.movementPattern
      : '';
  late bool _outdoor = widget.exercise?.isOutdoor ?? false;
  late bool _active = widget.exercise?.isActive ?? true;
  String _equipmentQuery = '';
  bool _slugEdited = false;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.exercise == null;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(Set<String> knownEquipment) async {
    final draft = ExerciseDraft(
      name: _name.text,
      slug: _slug.text.trim(),
      primary: _primary,
      secondary: _secondary,
      equipment: _equipment,
      movementPattern: _pattern,
      isOutdoor: _outdoor,
      isActive: _active,
      notes: _notes.text,
    );
    final problem = draft.problem(
      knownEquipment: knownEquipment,
      isNew: _isNew,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(adminRepositoryProvider);
      if (_isNew) {
        await repo.addExercise(draft);
      } else {
        await repo.updateExercise(widget.exercise!.id, draft);
      }
      refreshReferenceData(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on AdminWriteFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = <EquipmentItem>[
      for (final item
          in ref.watch(equipmentProvider).value ?? const <EquipmentItem>[])
        if (item.isInventoryItem) item,
    ]..sort((a, b) => a.label.compareTo(b.label));
    final known = <String>{for (final i in items) i.slug};
    final q = _equipmentQuery.trim().toLowerCase();
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: theme.textTheme.labelLarge),
    );

    return _SheetFrame(
      title: _isNew ? 'Add exercise' : widget.exercise!.name,
      subtitle: _isNew ? null : 'ID ${widget.exercise!.slug}',
      error: _error,
      saving: _saving,
      onSave: () => _save(known),
      scrolls: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) {
              if (_isNew && !_slugEdited) _slug.text = slugify(v);
            },
          ),
          if (_isNew) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _slug,
              decoration: const InputDecoration(
                labelText: 'ID',
                helperText: 'Stable ID. Cannot be changed later.',
              ),
              onChanged: (_) => _slugEdited = true,
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _pattern.isEmpty ? null : _pattern,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Movement pattern'),
            items: [
              for (final p in kMovementPatterns)
                DropdownMenuItem(
                  value: p,
                  child: Text(movementPatternLabel(p)),
                ),
            ],
            onChanged: (v) => setState(() => _pattern = v ?? ''),
          ),
          label('Primary muscles (lit up on the map)'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in MuscleGroup.values)
                FilterChip(
                  label: Text(muscleGroupLabel(g)),
                  selected: _primary.contains(g),
                  onSelected: (v) => setState(() {
                    v ? _primary.add(g) : _primary.remove(g);
                    _secondary.remove(g);
                  }),
                ),
            ],
          ),
          label('Secondary muscles (assist)'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in MuscleGroup.values)
                if (!_primary.contains(g))
                  FilterChip(
                    label: Text(muscleGroupLabel(g)),
                    selected: _secondary.contains(g),
                    onSelected: (v) => setState(
                      () => v ? _secondary.add(g) : _secondary.remove(g),
                    ),
                  ),
            ],
          ),
          label('Equipment it needs (${_equipment.length} picked)'),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Filter equipment',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _equipmentQuery = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (slug, name) in [
                ('bodyweight', 'Bodyweight'),
                ('outdoor', 'Outdoor'),
                for (final i in items) (i.slug, i.label),
              ])
                if (_equipment.contains(slug) ||
                    q.isEmpty ||
                    name.toLowerCase().contains(q))
                  FilterChip(
                    label: Text(name),
                    selected: _equipment.contains(slug),
                    onSelected: (v) => setState(
                      () => v ? _equipment.add(slug) : _equipment.remove(slug),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Done outdoors'),
            value: _outdoor,
            onChanged: (v) => setState(() => _outdoor = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: Text(
              'Retired exercises leave plans and the picker; logged history '
              'keeps them.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _AdminList extends StatelessWidget {
  const _AdminList({
    required this.search,
    required this.onSearch,
    required this.filters,
    required this.summary,
    required this.children,
  });

  final String search;
  final ValueChanged<String> onSearch;
  final List<Widget> filters;
  final String summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 96),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: search,
                ),
                onChanged: onSearch,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: filters),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                summary,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (children.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Nothing matches.')),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.child,
    required this.saving,
    required this.onSave,
    this.subtitle,
    this.error,
    this.scrolls = false,
  });

  final String title;
  final String? subtitle;
  final String? error;
  final bool saving;
  final VoidCallback onSave;
  final Widget child;

  /// True when the sheet is height-bounded and its body should scroll.
  final bool scrolls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: child,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (scrolls)
                Expanded(child: SingleChildScrollView(child: body))
              else
                Flexible(child: SingleChildScrollView(child: body)),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(error!, style: TextStyle(color: scheme.error)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: FilledButton(
                  onPressed: saving ? null : onSave,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Could not load.'),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

/// Used by the profile screen to show the admin badge in brand colours.
class AdminBadge extends StatelessWidget {
  const AdminBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(LionFitTokens.of(context).radiusSm),
      ),
      child: Text(
        'ADMIN',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSecondary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
