import 'package:flutter_test/flutter_test.dart';
import 'package:wavelog_mobile/core/utils/worked_before.dart';
import 'package:wavelog_mobile/data/models/qso_model.dart';

QsoModel qso(String call, String band, String mode, DateTime at,
        {String? dxcc, String? country, String? submode}) =>
    QsoModel(
      callsign: call,
      dateTimeOn: at,
      band: band,
      mode: mode,
      submode: submode,
      rstSent: '59',
      rstRcvd: '59',
      dxcc: dxcc,
      country: country,
      stationProfileId: 1,
    );

void main() {
  final today = DateTime.utc(2026, 10, 24, 12);
  final lastYear = DateTime.utc(2025, 5, 1, 10);
  final log = [
    qso('DL1ABC', '20m', 'SSB', lastYear, dxcc: '230', country: 'FED. REP. OF GERMANY'),
    qso('DL2XYZ', '40m', 'CW', lastYear, dxcc: '230', country: 'FED. REP. OF GERMANY'),
    qso('SP9AQG', '20m', 'SSB', today.subtract(const Duration(hours: 2)), country: 'POLAND'),
    qso('OK1AAA', '20m', 'MFSK', lastYear, country: 'CZECH REPUBLIC', submode: 'FT4'),
  ];

  WorkedStatus check(String call, String band, String mode,
          {String? dxcc, String? country, DateTime? day}) =>
      workedStatus(
        log: log,
        callsign: call,
        band: band,
        mode: mode,
        day: day ?? today,
        dxccId: dxcc,
        country: country,
      );

  test('an entity never worked is a new country', () {
    final s = check('JA1XYZ', '20m', 'SSB', dxcc: '339', country: 'Japan');
    expect(s.newCountry, isTrue);
    expect(s.newBand, isFalse);
    expect(s.newMode, isFalse);
  });

  test('worked entity: new band and new mode flagged separately', () {
    expect(check('DL5NEW', '15m', 'SSB', dxcc: '230').newBand, isTrue);
    expect(check('DL5NEW', '15m', 'SSB', dxcc: '230').newMode, isFalse);
    expect(check('DL5NEW', '20m', 'FM', dxcc: '230').newMode, isTrue);
    expect(check('DL5NEW', '20m', 'FM', dxcc: '230').newBand, isFalse);
    expect(check('DL5NEW', '40m', 'CW', dxcc: '230').isEmpty, isTrue);
  });

  test('country names match case-insensitively when there is no DXCC id', () {
    expect(check('SP5ABC', '20m', 'SSB', country: 'Poland').isEmpty, isTrue);
    expect(check('SP5ABC', '80m', 'SSB', country: 'Poland').newBand, isTrue);
  });

  test('a mode stored as the ADIF submode counts (FT4 as MFSK/FT4)', () {
    expect(check('OK2BBB', '20m', 'FT4', country: 'Czech Republic').isEmpty,
        isTrue);
  });

  test('without a country yet only the dupe check runs', () {
    expect(check('JA1XYZ', '20m', 'SSB').isEmpty, isTrue);
  });

  test('same call, band and mode on the same UTC day is a dupe', () {
    expect(check('sp9aqg', '20m', 'SSB').dupe, isTrue);
    expect(check('SP9AQG', '40m', 'SSB').dupe, isFalse);
    expect(check('SP9AQG', '20m', 'CW').dupe, isFalse);
    expect(
        check('SP9AQG', '20m', 'SSB', day: DateTime.utc(2026, 10, 25, 1)).dupe,
        isFalse);
    expect(check('DL1ABC', '20m', 'SSB').dupe, isFalse); // last year
  });
}
