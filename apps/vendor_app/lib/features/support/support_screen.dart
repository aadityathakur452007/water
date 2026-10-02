// Support screen: verify a dispute/quality task by id (from push/admin).
// Agree → resolved auto; disagree → under review + 48h admin triage.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'support_controller.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.controller});

  final SupportController controller;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _id = TextEditingController();
  final _note = TextEditingController();
  String _check = 'seal';
  bool _isQuality = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _id.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(bool agree) async {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    final ok = _isQuality
        ? await widget.controller.checkQuality(
            incidentId: id,
            agree: agree,
            check: _check,
            note: _note.text.trim(),
          )
        : await widget.controller.verifyComplaint(
            complaintId: id,
            agree: agree,
            note: _note.text.trim(),
          );
    if (mounted && widget.controller.notice != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.notice!)));
      widget.controller.clearNotice();
      if (ok) {
        _id.clear();
        _note.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Support / सहायता')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: ShodashaTheme.shape,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false, label: Text('Dispute')),
                      ButtonSegment(
                          value: true, label: Text('Quality')),
                    ],
                    selected: {_isQuality},
                    onSelectionChanged: (s) =>
                        setState(() => _isQuality = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _id,
                    decoration: InputDecoration(
                      labelText: _isQuality
                          ? 'Incident ID'
                          : 'Complaint ID',
                    ),
                  ),
                  if (_isQuality)
                    DropdownButtonFormField<String>(
                      initialValue: _check,
                      decoration:
                          const InputDecoration(labelText: 'Check'),
                      items: const [
                        DropdownMenuItem(
                            value: 'seal', child: Text('Seal')),
                        DropdownMenuItem(
                            value: 'smell', child: Text('Smell')),
                        DropdownMenuItem(
                            value: 'visual', child: Text('Visual')),
                      ],
                      onChanged: (v) =>
                          setState(() => _check = v ?? 'seal'),
                    ),
                  TextField(
                    controller: _note,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note (500 chars tak)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: c.submitting || _id.text.trim().isEmpty
                              ? null
                              : () => _submit(true),
                          child: const Text('Sahmat / Agree'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: c.submitting || _id.text.trim().isEmpty
                              ? null
                              : () => _submit(false),
                          child: const Text('Asahmat'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Quantity/deposit/cap vivaad system record se suljhte hain. Quality ke liye door check zaroori. 3-day window; water_quality 24h.',
            style: TextStyle(color: ShodashaTheme.muted),
          ),
        ],
      ),
    );
  }
}
