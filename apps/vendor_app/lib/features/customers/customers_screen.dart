// Customers screen: search + list (totals per customer) → detail sheet
// (stop rows + expected jars). States.md on every branch.

import 'package:flutter/material.dart';

import '../../core/cascade.dart';
import '../../core/theme.dart';
import '../../core/vendor_locale.dart';
import '../../shared/ui/app_button.dart';
import 'customers_controller.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.controller});

  final CustomersController controller;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    if (widget.controller.state == CustomersState.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.load();
      });
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _search.dispose();
    super.dispose();
  }

  void _openDetail(VendorCustomer c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ShodashaTheme.radiusSheet)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scroll) => _CustomerDetailSheet(
          customer: c,
          scroll: scroll,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(vtr('ग्राहक', 'Customers'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: TextField(
              controller: _search,
              onChanged: c.setQuery,
              decoration: InputDecoration(
                labelText: vtr('नाम या फ़ोन से खोजें', 'Search name or phone'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(CustomersController c) {
    switch (c.state) {
      case CustomersState.loading:
        return const Center(child: CircularProgressIndicator());
      case CustomersState.offline:
      case CustomersState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.error ?? 'Load nahi hua', textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Dobara try karein',
                  kind: AppButtonKind.primary,
                  expand: false,
                  onPressed: c.load,
                ),
              ],
            ),
          ),
        );
      case CustomersState.empty:
        return const Center(child: Text('Aaj koi customer nahi — route khali hai'));
      case CustomersState.loaded:
        final items = c.items;
        if (items.isEmpty) {
          return const Center(child: Text('Khoj me kuch nahi mila'));
        }
        return RefreshIndicator(
          onRefresh: c.load,
          child: CascadeScope(
            itemCount: items.length,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                final v = items[i];
                // Queue-tile row (reference cart-item rhythm): 48dp leading
                // mark + name/phone/facts + chevron. No info dropped.
                return CascadeItem(
                  index: i,
                  child: InkWell(
                    onTap: () => _openDetail(v),
                    borderRadius:
                        BorderRadius.circular(ShodashaTheme.radius),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        border: Border.all(color: ShodashaTheme.border),
                        borderRadius:
                            BorderRadius.circular(ShodashaTheme.radius),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: ShodashaTheme.minTarget,
                            height: ShodashaTheme.minTarget,
                            decoration: const BoxDecoration(
                              color: ShodashaTheme.blueTint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              color: ShodashaTheme.blue,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: ShodashaTheme.ink),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                if (v.phone != null)
                                  Text(v.phone!,
                                      style: const TextStyle(
                                          color: ShodashaTheme.muted,
                                          fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${v.total} stop • ${v.done} done • ${v.fullsExpected} fulls / ${v.emptiesExpected} empties',
                                  style: const TextStyle(
                                      color: ShodashaTheme.muted,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: ShodashaTheme.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
    }
  }
}

class _CustomerDetailSheet extends StatelessWidget {
  const _CustomerDetailSheet({required this.customer, required this.scroll});

  final VendorCustomer customer;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(customer.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(
              '${customer.fullsExpected} fulls • ${customer.emptiesExpected} empties wapas',
              style:
                  const TextStyle(color: ShodashaTheme.muted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: customer.stops.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final s = customer.stops[i];
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      border: Border.all(color: ShodashaTheme.border),
                      borderRadius:
                          BorderRadius.circular(ShodashaTheme.radius),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text('Stop ${s.seq}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                        Text(s.status,
                            style: const TextStyle(
                                color: ShodashaTheme.muted, fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
