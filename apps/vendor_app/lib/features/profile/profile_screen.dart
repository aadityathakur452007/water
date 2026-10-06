// Profile: vendor card from /auth/me + server profile (011_port Slice 1:
// GET/PATCH /vendor/profile, synced label) + language note +
// WhatsApp support + logout (own device only, server best-effort).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart' show kSupportPhone, ApiClient;
import '../../core/theme.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.auth,
    required this.meLoader,
    this.profileLoader,
    this.profileSaver,
    this.api,
  });

  final AuthController auth;
  final Future<Map<String, dynamic>> Function() meLoader;

  /// 011_port live branch (null = section hidden, old read-only card only).
  final Future<Map<String, dynamic>> Function()? profileLoader;
  final Future<Map<String, dynamic>> Function(Map<String, String> fields)?
      profileSaver;
  final ApiClient? api;

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

  List<dynamic> _leaves = [];
  bool _leavesLoading = false;

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
      await _loadLeaves();
    } catch (_) {
      _error = 'Profile load nahi hua';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLeaves() async {
    final api = widget.api;
    if (api == null) return;
    setState(() => _leavesLoading = true);
    try {
      final list = await api.listLeaves();
      if (mounted) setState(() => _leaves = list);
    } catch (_) {}
    if (mounted) setState(() => _leavesLoading = false);
  }

  Future<void> _requestLeaveDialog() async {
    final api = widget.api;
    if (api == null) return;
    DateTime? start;
    DateTime? end;
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Nayi Chutti Request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kripya chutti ki tareekh chunein taaki backup vendor route sambhal sake:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(start == null
                      ? 'Shuru tareekh (Start Date)'
                      : '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}'),
                  trailing: const Text('Select', style: TextStyle(color: ShodashaTheme.blue)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) {
                      setDlgState(() {
                        start = picked;
                        if (end != null && end!.isBefore(start!)) end = start;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(end == null
                      ? 'Aakhiri tareekh (End Date)'
                      : '${end!.year}-${end!.month.toString().padLeft(2, '0')}-${end!.day.toString().padLeft(2, '0')}'),
                  trailing: const Text('Select', style: TextStyle(color: ShodashaTheme.blue)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: start ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: start ?? DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) {
                      setDlgState(() => end = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Karan (Reason - Optional)',
                    hintText: 'Jaise: Shaadi, Bimari, Tyohar...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (start == null || end == null)
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('Request Bhejein'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && start != null && end != null && mounted) {
      final sStr = '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}';
      final eStr = '${end!.year}-${end!.month.toString().padLeft(2, '0')}-${end!.day.toString().padLeft(2, '0')}';
      try {
        await api.requestLeave(
          startDate: sStr,
          endDate: eStr,
          reason: reasonCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chutti request bhej di gayi hai! Admin review karega.')),
          );
          _loadLeaves();
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Request fail hui: $err')),
          );
        }
      }
    }
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
        if (widget.api != null) ...[
          Card(
            shape: ShodashaTheme.shape,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Chutti / Planned Leave',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: _leavesLoading ? null : _loadLeaves,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  const Text(
                    'Chutti par jaane se pehle request karein taaki route cover assign ho sake.',
                    style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _requestLeaveDialog,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Nayi Chutti Request Karein'),
                  ),
                  const SizedBox(height: 12),
                  if (_leavesLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_leaves.isEmpty)
                    const Text(
                      'Abhi koi leave request nahi hai.',
                      style: TextStyle(color: ShodashaTheme.muted, fontSize: 13),
                    )
                  else
                    ..._leaves.map((l) {
                      final item = l as Map<String, dynamic>;
                      final status = (item['status'] ?? 'pending').toString();
                      final color = status == 'approved'
                          ? ShodashaTheme.success
                          : (status == 'rejected' ? ShodashaTheme.danger : Colors.orange);
                      final label = status == 'approved'
                          ? 'Manzoor (Approved)'
                          : (status == 'rejected' ? 'Radd (Rejected)' : 'Under Review');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ShodashaTheme.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['start_date']} se ${item['end_date']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if ((item['reason'] ?? '').toString().isNotEmpty)
                                    Text(
                                      '${item['reason']}',
                                      style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                                    ),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                              backgroundColor: color.withValues(alpha: 0.1),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
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
