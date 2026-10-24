import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavelog_mobile/data/datasources/remote/wavelog_remote_datasource.dart';
import 'package:wavelog_mobile/data/models/callsign_lookup_model.dart';
import 'package:wavelog_mobile/l10n/app_localizations.dart';
import 'package:wavelog_mobile/presentation/screens/qso/add_qso_screen.dart';
import 'package:wavelog_mobile/providers/qso_provider.dart';
import 'package:wavelog_mobile/providers/remote_datasource_provider.dart';

class _OfflineRemote extends WavelogRemoteDatasource {
  _OfflineRemote() : super(dio: Dio());

  @override
  Future<CallsignLookupModel> lookupCallsign(
          {required String callsign, String? band, String? mode}) =>
      Future.error(Exception('offline'));
}

void main() {
  Future<void> pumpForm(WidgetTester tester, AddQsoScreen screen) async {
    SharedPreferences.setMockInitialValues({});
    // Tall phone-sized surface, so the whole form lays out.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wavelogRemoteDatasourceProvider.overrideWithValue(_OfflineRemote()),
        scopedQsoProvider.overrideWithValue(const AsyncValue.data([])),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ));
    await tester.pump();
  }

  testWidgets('a spot fills in the hunted park, summit and WWFF area',
      (tester) async {
    await pumpForm(
        tester,
        const AddQsoScreen(
          prefillCallsign: 'K1ABC',
          prefillPotaRef: 'US-1234',
          prefillSotaRef: 'W1/HA-001',
          prefillWwffRef: 'KFF-1234',
        ));
    // Unfolded, with the park as a chip and the other two in their fields.
    expect(find.widgetWithText(InputChip, 'US-1234'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'W1/HA-001'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'KFF-1234'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('without one the references stay available, folded away',
      (tester) async {
    await pumpForm(tester, const AddQsoScreen());
    final tile = find.widgetWithText(ExpansionTile, 'POTA / SOTA / WWFF');
    expect(tile, findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'POTA'), findsNothing);

    await tester.tap(tile);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.widgetWithText(TextFormField, 'POTA'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'SOTA'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'WWFF'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
