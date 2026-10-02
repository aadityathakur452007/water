// Stock screen (011_port inventory): today's loading sheet + live progress.
// No new endpoint — reads the RouteController the shell already owns
// (server owns sequencing; the app only displays).

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../route/route_controller.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.route});

  final RouteController route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock / स्टॉक')),
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 48, color: ShodashaTheme.muted),
                      const SizedBox(height: 12),
                      Text(route.error ?? 'Stock load nahi hua',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => route.load(),
                        child: const Text('Dobara try karein'),
                      ),
                    ],
                  ),
                ),
              );
            case RouteState.empty:
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
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
              padding: const EdgeInsets.all(16),
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
                          color: ShodashaTheme.muted, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _tile('Lene hain (fulls)', '${route.takeFulls} jar'),
                _tile('Wapas aane hain (empties)', '${route.expectEmpties} jar'),
                _tile('Stop done', '$done / ${stops.length}'),
                _tile('Stop baki', '$pending'),
                const SizedBox(height: 8),
                const Text(
                  'Loading sheet route se banti hai — triple commit par done badhta hai.',
                  style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
