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
          final stops = route.stops;
          final done = route.doneCount;
          final pending = stops.length - done;
          return RefreshIndicator(
            onRefresh: route.load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
