import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/vendor_locale.dart';
import '../../shared/ui/app_button.dart';

class RidersScreen extends StatefulWidget {
  const RidersScreen({super.key, required this.api});

  final ApiClient? api;

  @override
  State<RidersScreen> createState() => _RidersScreenState();
}

class _RidersScreenState extends State<RidersScreen> {
  List<dynamic> _riders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRiders();
  }

  Future<void> _loadRiders() async {
    if (widget.api == null) {
      setState(() {
        _loading = false;
        _riders = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api!.listRiders();
      if (mounted) {
        setState(() {
          _riders = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _openAddRiderDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? formError;
    bool busy = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShodashaTheme.radiusSheet),
        ),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        vtr('नया राइडर जोड़ें', 'Add Delivery Rider'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    vtr(
                      'राइडर अपने मोबाइल नंबर से सीधे राइडर ऐप में लॉगिन करेगा।',
                      'Rider logs in to the Rider App using this mobile number — no password needed.',
                    ),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: ShodashaTheme.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: vtr('राइडर का नाम', 'Rider Full Name'),
                      hintText: 'e.g. Ramesh Kumar',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          ShodashaTheme.radius,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: vtr(
                        'मोबाइल नंबर (10 अंक)',
                        'Mobile Number (10 digits)',
                      ),
                      hintText: 'e.g. 9876543210',
                      prefixText: '+91 ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          ShodashaTheme.radius,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      formError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ShodashaTheme.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: busy
                        ? 'Saving…'
                        : vtr('राइडर रजिस्टर करें', 'Register Rider'),
                    kind: AppButtonKind.primary,
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: busy
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            final phone = phoneCtrl.text.replaceAll(
                              RegExp(r'\D'),
                              '',
                            );
                            if (name.length < 2) {
                              setModalState(
                                () => formError = 'Enter a valid rider name',
                              );
                              return;
                            }
                            if (phone.length < 10) {
                              setModalState(
                                () => formError =
                                    'Enter a valid 10-digit phone number',
                              );
                              return;
                            }
                            setModalState(() {
                              busy = true;
                              formError = null;
                            });
                            try {
                              final rider = await widget.api!.createRider(
                                name: name,
                                phone: phone,
                              );
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                              }
                              if (mounted) {
                                _loadRiders();
                                final code = rider['access_code'] as String?;
                                if (code != null) {
                                  await _showCodeDialog(name, phone, code);
                                }
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setModalState(() {
                                  busy = false;
                                  formError = e.toString().replaceFirst(
                                    'Exception: ',
                                    '',
                                  );
                                });
                              }
                            }
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shows a freshly issued sign-in code. It is returned only once, so this
  /// dialog is the only place the vendor can hand it to the rider.
  Future<void> _showCodeDialog(String name, String phone, String code) {
    return showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(vtr('राइडर साइन-इन कोड', 'Rider sign-in code')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vtr(
                '$name की शिफ्ट $phone पर इस कोड से शुरू होगी। कोड केवल एक बार दिखता है।',
                '$name starts their shift on $phone with this code. It is shown only once.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(vtr('ठीक है', 'Done')),
          ),
        ],
      ),
    );
  }

  Future<void> _reissueCode(Map<String, dynamic> rider) async {
    final name = rider['name']?.toString() ?? 'Rider';
    final phone = rider['phone']?.toString() ?? '';
    try {
      final res = await widget.api!.reissueRiderCode(rider['id'].toString());
      final code = res['access_code'] as String?;
      if (code != null && mounted) await _showCodeDialog(name, phone, code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // Show the server's own words, not ApiException(code, status, …).
            content: Text(
              e is ApiException
                  ? e.message
                  : e.toString().replaceFirst('Exception: ', ''),
            ),
            backgroundColor: ShodashaTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(vtr('डिलीवरी राइडर', 'Delivery Riders')),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadRiders,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: ShodashaTheme.danger,
                      size: 40,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(label: 'Retry', onPressed: _loadRiders),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                // Credentials Helper Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.blueTint,
                    borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                    border: Border.all(
                      color: ShodashaTheme.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: ShodashaTheme.blue,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vtr(
                                'राइडर लॉगिन क्रेडेंशियल्स',
                                'Rider App Login Credentials',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: ShodashaTheme.blue,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vtr(
                                'राइडर शोडष राइडर ऐप में अपना रजिस्टर्ड मोबाइल नंबर और साइन-इन कोड डालकर लॉगिन करते हैं। कोड भूल जाने पर यहाँ की चाबी (🔑) से नया कोड बनाएँ।',
                                'Riders log in to the Shodasha Rider App with their registered mobile number and a sign-in code. Use the key icon to issue a new code if it is lost.',
                              ),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: ShodashaTheme.ink,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'REGISTERED RIDERS (${_riders.length})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: ShodashaTheme.muted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openAddRiderDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(vtr('राइडर जोड़ें', 'Add Rider')),
                      ),
                    ],
                  ),
                ),

                if (_riders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: ShodashaTheme.surface,
                      borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                      border: Border.all(color: ShodashaTheme.border),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.two_wheeler_outlined,
                          size: 48,
                          color: ShodashaTheme.muted,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          vtr(
                            'कोई राइडर नहीं जुड़ा है',
                            'No delivery riders registered yet',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          vtr(
                            'नीचे दिए गए बटन से अपने डिलीवरी बॉय का मोबाइल नंबर जोड़ें।',
                            'Add your delivery rider mobile numbers so they can access their route.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ShodashaTheme.muted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: vtr('+ नया राइडर जोड़ें', '+ Add Rider'),
                          kind: AppButtonKind.primary,
                          onPressed: _openAddRiderDialog,
                        ),
                      ],
                    ),
                  )
                else
                  ..._riders.map((r) {
                    final name = r['name']?.toString() ?? 'Rider';
                    final phone = r['phone']?.toString() ?? '';
                    final isSuspended =
                        r['suspended'] == 1 || r['suspended'] == true;
                    return Card(
                      shape: ShodashaTheme.shape,
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSuspended
                              ? ShodashaTheme.border
                              : ShodashaTheme.blueTint,
                          child: Icon(
                            Icons.two_wheeler_rounded,
                            color: isSuspended
                                ? ShodashaTheme.muted
                                : ShodashaTheme.blue,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          phone,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ShodashaTheme.muted,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isSuspended
                                    ? ShodashaTheme.border
                                    : ShodashaTheme.blueTint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isSuspended ? 'Suspended' : 'Active Rider',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSuspended
                                      ? ShodashaTheme.muted
                                      : ShodashaTheme.blue,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: vtr(
                                'नया साइन-इन कोड',
                                'New sign-in code',
                              ),
                              icon: const Icon(Icons.key_rounded, size: 20),
                              onPressed: () => _reissueCode(
                                Map<String, dynamic>.from(r as Map),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
      floatingActionButton: _riders.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openAddRiderDialog,
              backgroundColor: ShodashaTheme.ink,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(vtr('राइडर जोड़ें', 'Add Rider')),
            )
          : null,
    );
  }
}
