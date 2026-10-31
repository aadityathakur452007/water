import 'package:flutter/material.dart';

import '../../core/api_client.dart' show kSupportPhone;
import '../../core/theme.dart';
import '../../core/vendor_locale.dart';

class MoreHubScreen extends StatelessWidget {
  const MoreHubScreen({
    super.key,
    required this.onOpenCustomers,
    required this.onOpenStock,
    required this.onOpenSync,
    required this.onOpenDuty,
    required this.onOpenProfile,
    required this.onWhatsApp,
    required this.onLogout,
    this.pendingSyncCount = 0,
    this.onDuty = false,
  });

  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenStock;
  final VoidCallback onOpenSync;
  final VoidCallback onOpenDuty;
  final VoidCallback onOpenProfile;
  final VoidCallback onWhatsApp;
  final VoidCallback onLogout;
  final int pendingSyncCount;
  final bool onDuty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(vtr('अधिक सेवाएं', 'More Tools')),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        children: [
          // Duty status quick tile
          Card(
            shape: ShodashaTheme.shape,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            color: onDuty ? ShodashaTheme.blueTint : ShodashaTheme.surface,
            child: ListTile(
              leading: Icon(
                onDuty ? Icons.check_circle_outline : Icons.pause_circle_outline,
                color: onDuty ? ShodashaTheme.blue : ShodashaTheme.muted,
                size: 28,
              ),
              title: Text(
                onDuty ? 'Duty: Active (ड्यूटी चालू)' : 'Duty: Off (ड्यूटी बंद)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                onDuty
                    ? 'Deliveries enabled for your route'
                    : 'Turn on duty to receive delivery stops',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenDuty,
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              'TOOLS & OPERATIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.muted,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Card(
            shape: ShodashaTheme.shape,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.people_outline, color: ShodashaTheme.ink),
                  title: Text(vtr('ग्राहक', 'Customers')),
                  subtitle: const Text('Aaj ke grahak, khoj ke saath'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenCustomers,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined, color: ShodashaTheme.ink),
                  title: Text(vtr('स्टॉक', 'Stock')),
                  subtitle: Text(vtr('लोडिंग शीट: भरे व खाली जार', 'Loading sheet: fulls & empty cans')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenStock,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Badge(
                    isLabelVisible: pendingSyncCount > 0,
                    label: Text('$pendingSyncCount'),
                    child: const Icon(Icons.sync_outlined, color: ShodashaTheme.ink),
                  ),
                  title: Text(vtr('सिंक स्थिति', 'Sync Log')),
                  subtitle: Text(
                    pendingSyncCount > 0
                        ? '$pendingSyncCount pending sync'
                        : 'All offline records synced',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenSync,
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              'ACCOUNT & SUPPORT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ShodashaTheme.muted,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Card(
            shape: ShodashaTheme.shape,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline, color: ShodashaTheme.ink),
                  title: Text(vtr('प्रोफ़ाइल', 'Profile')),
                  subtitle: const Text('Dukaan profile, language & settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenProfile,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined, color: ShodashaTheme.ink),
                  title: Text('WhatsApp Help ($kSupportPhone)'),
                  subtitle: const Text('Direct desk assistance'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: onWhatsApp,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: ShodashaTheme.danger),
                  title: const Text(
                    'Logout (लॉग आउट)',
                    style: TextStyle(color: ShodashaTheme.danger, fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: ShodashaTheme.shape,
                        title: const Text('Logout karein?'),
                        content: const Text('Kya aap pakka logout karna chahte hain?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ShodashaTheme.danger,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) onLogout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

