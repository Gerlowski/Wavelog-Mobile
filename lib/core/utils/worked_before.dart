import '../../data/models/qso_model.dart';

/// What the log already holds for the contact being entered: whether its
/// DXCC entity is new overall, on this band or in this mode, and whether
/// the same contact was already logged today (a dupe).
class WorkedStatus {
  final bool newCountry;
  final bool newBand;
  final bool newMode;
  final bool dupe;

  const WorkedStatus({
    this.newCountry = false,
    this.newBand = false,
    this.newMode = false,
    this.dupe = false,
  });

  bool get isEmpty => !newCountry && !newBand && !newMode && !dupe;
}

/// Checks [callsign] on [band]/[mode] against [log] (the QSOs in scope).
///
/// The entity is matched by DXCC id when both sides have one, else by
/// country name, case-insensitively (Wavelog stores names upper-case, its
/// lookup returns them title-case). Without either — before the callsign
/// lookup answers — only the dupe check runs. A dupe is the same callsign,
/// band and mode on the same UTC day as [day].
WorkedStatus workedStatus({
  required List<QsoModel> log,
  required String callsign,
  required String band,
  required String mode,
  required DateTime day,
  String? dxccId,
  String? country,
}) {
  final call = callsign.trim().toUpperCase();
  final b = band.toLowerCase();
  final m = mode.toUpperCase();
  final d = day.toUtc();
  final name = country?.trim().toUpperCase();

  bool sameMode(QsoModel q) =>
      q.mode.toUpperCase() == m || q.submode?.toUpperCase() == m;

  bool sameEntity(QsoModel q) {
    if (dxccId != null && q.dxcc != null) return q.dxcc == dxccId;
    return name != null &&
        name.isNotEmpty &&
        q.country?.trim().toUpperCase() == name;
  }

  final hasEntity = dxccId != null || (name != null && name.isNotEmpty);
  var entityWorked = false, entityOnBand = false, entityInMode = false;
  var dupe = false;
  for (final q in log) {
    final onBand = q.band.toLowerCase() == b;
    if (hasEntity && sameEntity(q)) {
      entityWorked = true;
      entityOnBand |= onBand;
      entityInMode |= sameMode(q);
    }
    if (!dupe && onBand && q.callsign.toUpperCase() == call && sameMode(q)) {
      final t = q.dateTimeOn.toUtc();
      dupe = t.year == d.year && t.month == d.month && t.day == d.day;
    }
  }
  return WorkedStatus(
    newCountry: hasEntity && !entityWorked,
    newBand: entityWorked && !entityOnBand,
    newMode: entityWorked && !entityInMode,
    dupe: dupe,
  );
}
