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
  Future<void> pumpForm(WidgetTester tester) async {
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
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddQsoScreen(),
      ),
    ));
    await tester.pump();
  }

  EditableText freqField(WidgetTester tester) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .firstWhere((e) =>
          e.keyboardType ==
          const TextInputType.numberWithOptions(decimal: true));

  EditableText focused(WidgetTester tester) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .firstWhere((e) => e.focusNode.hasFocus);

  testWidgets('Enter after the callsign goes to the report, then onward',
      (tester) async {
    await pumpForm(tester);
    // The frequency, as the radio or the operator would have filled it in.
    freqField(tester).controller.text = '14.200';
    await tester.enterText(find.byType(TextFormField).first, 'SP9AQG');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    await tester.pump(); // the input connection follows the focus
    var f = focused(tester);
    expect(f.controller.text, '59'); // RST sent, all selected
    expect(f.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2));
    expect(f.textInputAction, TextInputAction.next);

    f.onSubmitted!(f.controller.text); // Enter on the report field
    await tester.pump();
    f = focused(tester);
    expect(f.controller.text, '59'); // RST rcvd, Enter there saves
    expect(f.textInputAction, TextInputAction.done);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('without a frequency Enter after the callsign asks for it',
      (tester) async {
    await pumpForm(tester);
    freqField(tester).controller.text = '';
    await tester.enterText(find.byType(TextFormField).first, 'SP9AQG');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    await tester.pump(); // the input connection follows the focus
    expect(focused(tester).keyboardType,
        const TextInputType.numberWithOptions(decimal: true));
    await tester.pump(const Duration(seconds: 1));
  });
}
