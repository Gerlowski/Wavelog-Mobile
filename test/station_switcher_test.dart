import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavelog_mobile/data/models/station_model.dart';
import 'package:wavelog_mobile/l10n/app_localizations.dart';
import 'package:wavelog_mobile/presentation/widgets/station/station_switcher_sheet.dart';
import 'package:wavelog_mobile/providers/station_provider.dart';

const _home = StationModel(
    id: 1, profileName: 'Lomza', callsign: 'SP4BL', gridSquare: 'KO13AE');
const _field = StationModel(
    id: 2, profileName: 'Teren1', callsign: 'SP4BL/P', gridSquare: 'KO13AE');

/// The station list without the network, recording what gets activated.
class _FakeStations extends StationNotifier {
  final activated = <StationModel>[];

  @override
  Future<List<StationModel>> build() async => [_home, _field];

  @override
  Future<void> activate(StationModel station) async => activated.add(station);
}

void main() {
  testWidgets('one tap in the switcher makes a location active',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeStations();
    await tester.pumpWidget(ProviderScope(
      overrides: [stationProvider.overrideWith(() => fake)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStationSwitcher(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Lomza'), findsOneWidget);
    expect(find.text('SP4BL/P · KO13AE'), findsOneWidget);

    await tester.tap(find.text('Teren1'));
    await tester.pumpAndSettle();
    expect(fake.activated.single.id, 2);
    expect(find.text('Teren1'), findsNothing); // the sheet closed
    expect(find.text('SP4BL/P set as active station'), findsOneWidget);
  });
}
