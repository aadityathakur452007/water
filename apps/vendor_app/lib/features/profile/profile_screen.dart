// Profile: vendor card from /auth/me + server profile (011_port Slice 1:
// GET/PATCH /vendor/profile, synced label) + language note +
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
    this.profileLoader,
    this.profileSaver,
  });

  final AuthController auth;
  final Future<Map<String, dynamic>> Function() meLoader;

  /// 011_port live branch (null = section hidden, old read-only card only).
  final Future<Map<String, dynamic>> Function()? profileLoader;
  final Future<Map<String, dynamic>> Function(Map<String, String> fields)?
      profileSaver;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;

  /// Server profile branch (011_port).
  Map<String, dynamic>? _profile;
  bool _saving = false;
  String? _profileNotice;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _hours;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _address = TextEditingController();
    _hours = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _me = await widget.meLoader();
      final loader = widget.profileLoader;
      if (loader != null) {
        _profile = await loader();
        _name.text = (_profile?['name'] ?? '') as String;
        _phone.text = (_profile?['phone'] ?? '') as String;
        _address.text = (_profile?['address'] ?? '') as String;
        _hours.text = (_profile?['hours'] ?? '') as String;
      }
    } catch (_) {
      _error = 'Profile load nahi hua';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/919302190067');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _saveProfile() async {
    final saver = widget.profileSaver;
    if (saver == null || _saving) return;
    setState(() {
      _saving = true;
      _profileNotice = null;
    });
    try {
      final saved = await saver({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'hours': _hours.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _profileNotice = 'Synced — doosre device par dikhega';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _profileNotice = 'Save nahi hua — dobara try karein');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        if (widget.profileLoader != null)
          Card(
            shape: ShodashaTheme.shape,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Dukaan profile (server par synced)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(labelText: 'Naam')),
                  TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Phone')),
                  TextField(
                      controller: _address,
                      decoration:
                          const InputDecoration(labelText: 'Pata')),
                  TextField(
                      controller: _hours,
                      decoration: const InputDecoration(
                          labelText: 'Hours (jaise 8-8)')),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _saveProfile,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save karein'),
                  ),
                  if (_profileNotice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_profileNotice!,
                          style: const TextStyle(
                              color: ShodashaTheme.muted, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
        if (widget.profileLoader != null) const SizedBox(height: 12),
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
