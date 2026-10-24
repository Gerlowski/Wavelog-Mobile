import '../../data/models/qso_model.dart';

/// What the log already holds for [callsign] in the running contest: the
/// QSO that makes this one a dupe (same band), if any, and the other bands
/// the station was already worked on.
class ContestWorked {
  final QsoModel? dupeOf;
  final List<String> otherBands;

  const ContestWorked({this.dupeOf, this.otherBands = const []});

  bool get isEmpty => dupeOf == null && otherBands.isEmpty;
}

/// How far back a contest without a session (just a contest ID typed in)
/// is taken to reach: covers a 48-hour contest, not last year's edition of
/// the same contest ID.
const kContestWindowWithoutSession = Duration(hours: 48);

/// Checks [callsign] on [band] against the QSOs of contest [contestId]
/// logged from [from] on. One QSO per band is the common contest rule, so
/// the same call on the same band is a dupe; other bands are listed.
/// Calls compare without case.
ContestWorked contestWorked({
  required Iterable<QsoModel> log,
  required String callsign,
  required String band,
  required String contestId,
  required DateTime from,
}) {
  final call = callsign.trim().toUpperCase();
  final id = contestId.trim().toUpperCase();
  if (call.isEmpty || id.isEmpty) return const ContestWorked();
  final b = band.toLowerCase();
  final start = from.toUtc();

  QsoModel? dupe;
  final other = <String>{};
  for (final q in log) {
    if (q.callsign.trim().toUpperCase() != call) continue;
    if (q.contestId?.trim().toUpperCase() != id) continue;
    if (q.dateTimeOn.toUtc().isBefore(start)) continue;
    if (q.band.toLowerCase() == b) {
      if (dupe == null || q.dateTimeOn.isAfter(dupe.dateTimeOn)) dupe = q;
    } else {
      other.add(q.band.toLowerCase());
    }
  }
  return ContestWorked(dupeOf: dupe, otherBands: other.toList()..sort());
}
