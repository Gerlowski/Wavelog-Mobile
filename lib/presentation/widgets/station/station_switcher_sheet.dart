import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/l10n_extension.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/station_provider.dart';

/// Quick switch of the active station location (e.g. home / portable):
/// a bottom sheet listing the locations, one tap activates one. Opened from
/// the drawer header and the home screen's callsign chip.
Future<void> showStationSwitcher(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _StationSwitcherSheet(),
    );

class _StationSwitcherSheet extends ConsumerWidget {
  const _StationSwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final activeId =
        ref.watch(settingsProvider.select((s) => s.activeStationProfileId));
    final stations = ref.watch(stationProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(l10n.activeStation,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: stations.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in list)
                      ListTile(
                        leading: Icon(
                          s.id == activeId
                              ? Icons.check_circle
                              : Icons.cell_tower,
                          color: s.id == activeId ? cs.primary : null,
                        ),
                        title: Text(s.profileName),
                        subtitle: Text([
                          s.callsign,
                          if (s.gridSquare?.isNotEmpty == true) s.gridSquare!,
                        ].join(' · ')),
                        selected: s.id == activeId,
                        onTap: () async {
                          // Everything the sheet's context and ref give is
                          // taken before closing it.
                          final messenger = ScaffoldMessenger.of(context);
                          final notifier = ref.read(stationProvider.notifier);
                          final msg = l10n.stationActivated(s.callsign);
                          Navigator.pop(context);
                          if (s.id == activeId) return;
                          await notifier.activate(s);
                          messenger
                            ..clearSnackBars()
                            ..showSnackBar(SnackBar(content: Text(msg)));
                        },
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(l10n.stationSetup),
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                router.push('/stations');
              },
            ),
          ],
        ),
      ),
    );
  }
}
