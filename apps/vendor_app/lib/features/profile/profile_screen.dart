// Profile: read-only vendor card from /auth/me + language note +
// WhatsApp support + logout (own device only, server best-effort).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.auth,
    required this.meLoader,
  });

  final AuthController auth;
  final Future<Map<String, dynamic>> Function() meLoader;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _me = await widget.meLoader();
    } catch (_) {
      _error = 'Profile load nahi hua';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/919302190067');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile / प्रोफाइल')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Dobara try karein'),
              ),
            ],
          ),
        ),
      );
    }
    final user = (_me?['user'] as Map<String, dynamic>?) ?? {};
    final phone = (user['phone'] ?? '') as String;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: ShodashaTheme.shape,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((user['name'] ?? 'Vendor') as String,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text(phone),
                const SizedBox(height: 4),
                const Text('Role: vendor • Bhasha: Hindi',
                    style: TextStyle(color: ShodashaTheme.muted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _whatsapp,
          icon: const Icon(Icons.support_agent_outlined),
          label: Text('WhatsApp help ($kSupportPhone)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await widget.auth.logout();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
        ),
      ],
    );
  }
}
