// Customers screen: search + list (totals per customer) → detail sheet
// (stop rows + expected jars). States.md on every branch.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
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
      appBar: AppBar(title: const Text('Customers / ग्राहक')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: c.setQuery,
              decoration: const InputDecoration(
                labelText: 'Naam / phone se khojein',
                prefixIcon: Icon(Icons.search),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.error ?? ''),
              const SizedBox(height: 8),
              TextButton(onPressed: c.load, child: const Text('Dobara try karein')),
            ],
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
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final v = items[i];
              return InkWell(
                onTap: () => _openDetail(v),
                borderRadius: BorderRadius.circular(ShodashaTheme.radius),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: ShodashaTheme.border),
                    borderRadius:
                        BorderRadius.circular(ShodashaTheme.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ShodashaTheme.ink)),
                      if (v.phone != null)
                        Text(v.phone!,
                            style: const TextStyle(
                                color: ShodashaTheme.muted, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        '${v.total} stop • ${v.done} done • ${v.fullsExpected} fulls / ${v.emptiesExpected} empties',
                        style: const TextStyle(
                            color: ShodashaTheme.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            },
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(customer.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(
              '${customer.fullsExpected} fulls • ${customer.emptiesExpected} empties wapas',
              style:
                  const TextStyle(color: ShodashaTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: customer.stops.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = customer.stops[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
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
                                color: ShodashaTheme.muted, fontSize: 13)),
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
