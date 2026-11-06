/// The past-workouts filter: a range plus an optional muscle group.
///
/// Two kinds of range, matching the two controls on the screen:
///
/// * [RecentDays] - the slider, 1-7 days ending today. The default is 7, so
///   the screen opens on "the last week".
/// * [CalendarWeek] - the dropdown, Monday-Sunday weeks going back up to a
///   month (this week and the three before it).
///
/// Pure Dart.
library;

import '../../../core/training/models.dart';
import '../../workout/domain/workout_models.dart';

/// How far back the dropdown reaches: this week + 3 = about a month.
const int kHistoryWeeksBack = 3;
const int kMaxRecentDays = 7;

sealed class HistoryRange {
  const HistoryRange();

  /// Inclusive first and last calendar day.
  (DateTime, DateTime) bounds(DateTime asOf);

  String label(DateTime asOf);
}

final class RecentDays extends HistoryRange {
  const RecentDays(this.days)
    : assert(days >= 1 && days <= kMaxRecentDays, 'Slider is 1-7 days');

  final int days;

  @override
  (DateTime, DateTime) bounds(DateTime asOf) {
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    return (DateTime(today.year, today.month, today.day - (days - 1)), today);
  }

  @override
  String label(DateTime asOf) => days == 1 ? 'Today' : 'Last $days days';

  @override
  bool operator ==(Object other) => other is RecentDays && other.days == days;

  @override
  int get hashCode => days.hashCode;
}

final class CalendarWeek extends HistoryRange {
  const CalendarWeek(this.weeksAgo)
    : assert(weeksAgo >= 0 && weeksAgo <= kHistoryWeeksBack, '0-3 weeks back');

  /// 0 = this week.
  final int weeksAgo;

  @override
  (DateTime, DateTime) bounds(DateTime asOf) {
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1) - 7 * weeksAgo,
    );
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return (monday, weeksAgo == 0 ? today : sunday);
  }

  @override
  String label(DateTime asOf) {
    if (weeksAgo == 0) return 'This week';
    if (weeksAgo == 1) return 'Last week';
    final (monday, _) = bounds(asOf);
    return 'Week of ${_months[monday.month - 1]} ${monday.day}';
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarWeek && other.weeksAgo == weeksAgo;

  @override
  int get hashCode => weeksAgo.hashCode + 100;
}

final class HistoryFilter {
  const HistoryFilter({this.range = const RecentDays(7), this.muscle});

  final HistoryRange range;

  /// Null = every muscle.
  final MuscleGroup? muscle;

  HistoryFilter withRange(HistoryRange range) =>
      HistoryFilter(range: range, muscle: muscle);

  HistoryFilter withMuscle(MuscleGroup? muscle) =>
      HistoryFilter(range: range, muscle: muscle);
}

/// One exercise on one day, with its sets in order.
final class HistoryEntry {
  const HistoryEntry({required this.exercise, required this.sets});

  final CatalogExercise exercise;
  final List<SetRecord> sets;
}

final class HistoryDay {
  const HistoryDay({required this.day, required this.entries});

  final DateTime day;
  final List<HistoryEntry> entries;

  int get setCount => entries.fold(0, (sum, e) => sum + e.sets.length);
}

/// Applies [filter] and groups the result newest day first. A muscle filter
/// keeps an exercise when that muscle is a primary **or** secondary mover -
/// "what touched my triceps" includes bench press.
List<HistoryDay> applyHistoryFilter({
  required Iterable<SetRecord> sets,
  required Map<String, CatalogExercise> exercisesById,
  required HistoryFilter filter,
  required DateTime asOf,
}) {
  final (first, last) = filter.range.bounds(asOf);
  final byDay = <DateTime, Map<String, List<SetRecord>>>{};
  for (final set in sets) {
    if (set.performedOn.isBefore(first) || set.performedOn.isAfter(last)) {
      continue;
    }
    final exercise = exercisesById[set.exerciseId];
    if (exercise == null) continue;
    final muscle = filter.muscle;
    if (muscle != null && !exercise.allMuscleGroups.contains(muscle)) continue;
    byDay
        .putIfAbsent(set.performedOn, () => {})
        .putIfAbsent(set.exerciseId, () => [])
        .add(set);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      HistoryDay(
        day: day,
        entries: [
          for (final MapEntry(key: id, value: logged) in byDay[day]!.entries)
            HistoryEntry(
              exercise: exercisesById[id]!,
              sets: logged..sort((a, b) => a.setIndex.compareTo(b.setIndex)),
            ),
        ],
      ),
  ];
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
