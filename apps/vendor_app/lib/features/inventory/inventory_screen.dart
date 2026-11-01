// Stock screen (011_port inventory): today's loading sheet + live progress.
// No new endpoint — reads the RouteController the shell already owns
// (server owns sequencing; the app only displays).

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vendor_locale.dart';
import '../../shared/ui/app_button.dart';
import '../route/route_controller.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.route});

  final RouteController route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(vtr('स्टॉक', 'Stock'))),
      body: ListenableBuilder(
        listenable: route,
        builder: (context, _) {
          // S4: never show "0 jar" while the route is still loading/failing.
          switch (route.state) {
            case RouteState.loading:
              return const Center(child: CircularProgressIndicator());
            case RouteState.offline:
            case RouteState.error:
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 48, color: ShodashaTheme.muted),
                      const SizedBox(height: AppSpacing.md),
                      Text(route.error ?? 'Stock load nahi hua',
                          textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: 'Dobara try karein',
                        kind: AppButtonKind.primary,
                        expand: false,
                        onPressed: () => route.load(),
                      ),
                    ],
                  ),
                ),
              );
            case RouteState.empty:
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    'Aaj koi route nahi — stock sheet khali hai',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            case RouteState.loaded:
              break;
          }
          final stops = route.stops;
          final done = route.doneCount;
          final pending = stops.length - done;
          return RefreshIndicator(
            onRefresh: route.load,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                // Section-header row: label left, live progress right.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Aaj ka stock',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    Text(
                      '$done/${stops.length} done',
                      style: const TextStyle(
                          color: ShodashaTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _tile('Lene hain (fulls)', '${route.takeFulls} jar'),
                _tile('Wapas aane hain (empties)', '${route.expectEmpties} jar'),
                _tile('Stop done', '$done / ${stops.length}'),
                _tile('Stop baki', '$pending'),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Loading sheet route se banti hai — triple commit par done badhta hai.',
                  style: TextStyle(color: ShodashaTheme.muted, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tile(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: ShodashaTheme.border),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: ShodashaTheme.muted)),
          ),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}
