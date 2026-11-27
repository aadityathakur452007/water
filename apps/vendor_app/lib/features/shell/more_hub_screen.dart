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
    this.onOpenRiders,
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
  final VoidCallback? onOpenRiders;
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
                onDuty
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
                color: onDuty ? ShodashaTheme.blue : ShodashaTheme.muted,
                size: 28,
              ),
              title: Text(
                onDuty
                    ? vtr('ड्यूटी चालू है', 'Duty: Active')
                    : vtr('ड्यूटी बंद है', 'Duty: Off'),
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
              'Tools & operations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          Card(
            shape: ShodashaTheme.shape,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.people_outline,
                    color: ShodashaTheme.ink,
                  ),
                  title: Text(vtr('ग्राहक', 'Customers')),
                  subtitle: Text(vtr('आज के ग्राहक और खोज', "Today's customers and search")),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenCustomers,
                ),
                if (onOpenRiders != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.two_wheeler_outlined,
                      color: ShodashaTheme.ink,
                    ),
                    title: Text(vtr('डिलीवरी राइडर', 'Delivery Riders')),
                    subtitle: Text(
                      vtr(
                        'राइडर जोड़ें व क्रेडेंशियल्स देखें',
                        'Manage fleet riders & login credentials',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onOpenRiders,
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.inventory_2_outlined,
                    color: ShodashaTheme.ink,
                  ),
                  title: Text(vtr('स्टॉक', 'Stock')),
                  subtitle: Text(
                    vtr(
                      'लोडिंग शीट: भरे व खाली जार',
                      'Loading sheet: fulls & empty cans',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenStock,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Badge(
                    isLabelVisible: pendingSyncCount > 0,
                    label: Text('$pendingSyncCount'),
                    child: const Icon(
                      Icons.sync_outlined,
                      color: ShodashaTheme.ink,
                    ),
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
              'Account & support',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          Card(
            shape: ShodashaTheme.shape,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.person_outline,
                    color: ShodashaTheme.ink,
                  ),
                  title: Text(vtr('प्रोफ़ाइल', 'Profile')),
                  subtitle: Text(vtr('दुकान प्रोफ़ाइल, भाषा और सेटिंग्स', 'Shop profile, language & settings')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenProfile,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.support_agent_outlined,
                    color: ShodashaTheme.ink,
                  ),
                  title: Text('WhatsApp Help ($kSupportPhone)'),
                  subtitle: const Text('Direct desk assistance'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: onWhatsApp,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.logout,
                    color: ShodashaTheme.danger,
                  ),
                  title: Text(
                    vtr('लॉग आउट', 'Log out'),
                    style: const TextStyle(
                      color: ShodashaTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: ShodashaTheme.shape,
                        title: Text(vtr('लॉग आउट करें?', 'Log out?')),
                        content: Text(
                          vtr('क्या आप लॉग आउट करना चाहते हैं?', 'Are you sure you want to log out?'),
                        ),
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
