part of '../subscription_screen.dart';

class _PauseSheet extends StatefulWidget {
  const _PauseSheet();

  @override
  State<_PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends State<_PauseSheet> {
  String _scenario = '1_day';
  late DateTime _from;
  late DateTime _to;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyScenario('1_day');
  }

  void _applyScenario(String scenario) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    setState(() {
      _scenario = scenario;
      _error = null;
      switch (scenario) {
        case '1_day':
          _from = tomorrow;
          _to = tomorrow;
          break;
        case '2_days':
          _from = tomorrow;
          _to = tomorrow.add(const Duration(days: 1));
          break;
        case '1_week':
          _from = tomorrow;
          _to = tomorrow.add(const Duration(days: 6));
          break;
        case 'indefinite':
          _from = tomorrow;
          _to = tomorrow.add(const Duration(days: 365));
          break;
        case 'custom':
          _from = tomorrow;
          _to = tomorrow.add(const Duration(days: 7));
          break;
      }
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
      _scenario = 'custom';
      _error = null;
    });
  }

  void _confirm() {
    if (_to.compareTo(_from) < 0) {
      setState(() => _error = subStrings['errRange']);
      return;
    }
    Navigator.of(
      context,
    ).pop('${ApiClient.dateOnly(_from)}|${ApiClient.dateOnly(_to)}');
  }

  Widget _scenarioChips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final s in const [
        ('1_day', '1 Day'),
        ('2_days', '2 Days'),
        ('1_week', '1 Week'),
        ('indefinite', 'Until I Resume'),
        ('custom', 'Custom Dates'),
      ])
        ChoiceChip(
          label: Text(s.$2),
          selected: _scenario == s.$1,
          selectedColor: ShodashaTheme.tealTint,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _scenario == s.$1 ? ShodashaTheme.tealDeep : ShodashaTheme.ink,
          ),
          side: BorderSide(
            color: _scenario == s.$1 ? ShodashaTheme.teal : ShodashaTheme.border,
          ),
          backgroundColor: ShodashaTheme.surface,
          onSelected: (_) => _applyScenario(s.$1),
        ),
    ],
  );

  Widget _scenarioSummary() {
    String text;
    if (_scenario == '1_day') {
      text = 'Deliveries will pause for tomorrow only and resume automatically the next day.';
    } else if (_scenario == '2_days') {
      text = 'Deliveries will pause for the next 2 days.';
    } else if (_scenario == '1_week') {
      text = 'Deliveries will pause for 7 days (1 week).';
    } else if (_scenario == 'indefinite') {
      text = 'Deliveries will pause starting tomorrow until you choose to resume. You can restart anytime with 1 tap.';
    } else {
      text = 'Pause from ${_from.day}/${_from.month} to ${_to.day}/${_to.month}.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ShodashaTheme.tealTint,
        borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
        border: Border.all(color: ShodashaTheme.teal.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ShodashaTheme.tealDeep,
          height: 1.35,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subStrings['pauseTitle']!,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: ShodashaTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subStrings['pauseBody']!,
          style: const TextStyle(
            fontSize: 13,
            height: 1.35,
            color: ShodashaTheme.muted,
          ),
        ),
        const SizedBox(height: 16),
        _scenarioChips(),
        const SizedBox(height: 12),
        _scenarioSummary(),
        if (_scenario == 'custom') ...[
          const SizedBox(height: 12),
          _dateRow(
            label: subStrings['fromDate']!,
            date: _from,
            onTap: () => _pickDate(isFrom: true),
          ),
          const SizedBox(height: 8),
          _dateRow(
            label: subStrings['toDate']!,
            date: _to,
            onTap: () => _pickDate(isFrom: false),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ShodashaTheme.danger,
              ),
            ),
          ),
        const SizedBox(height: 16),
        AppButton(
          label: subStrings['pauseConfirm']!,
          kind: AppButtonKind.primary,
          onPressed: _confirm,
        ),
      ],
    ),
  );

  Widget _dateRow({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ShodashaTheme.ink,
          ),
        ),
      ),
      OutlinedButton(onPressed: onTap, child: Text(ApiClient.dateOnly(date))),
    ],
  );
}

/// Cancellation reason + refund destination; the server computes refunds.
class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _upi = TextEditingController();
  bool _touched = false;
  String _reason = 'I don\'t need jars anymore';

  bool get _upiOk =>
      RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}$').hasMatch(_upi.text.trim());

  void _confirm() {
    setState(() => _touched = true);
    if (!_upiOk) return;
    Navigator.of(context).pop({'reason': _reason, 'upi_id': _upi.text.trim()});
  }

  static const List<String> _reasons = [
    "I don't need jars anymore",
    'Moving to another city or area',
    "Delivery time doesn't suit me",
    'Quality or service issue',
    'Something else',
  ];

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cancel_outlined,
                color: ShodashaTheme.danger,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subStrings['cancelTitle']!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ShodashaTheme.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: subStrings['close'],
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShodashaTheme.bg,
              border: Border.all(color: ShodashaTheme.border),
              borderRadius: BorderRadius.circular(ShodashaTheme.radius),
            ),
            child: Text(
              subStrings['cancelBody']!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: ShodashaTheme.muted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            subStrings['cancelReason']!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: [
              for (final reason in _reasons)
                DropdownMenuItem(
                  value: reason,
                  child: Text(
                    reason,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
          ),
          const SizedBox(height: 14),
          Text(
            subStrings['cancelUpi']!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _upi,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. 9876543210@upi',
              helperText: 'Used only if a refund is due after pickup.',
              errorText: _touched && !_upiOk
                  ? 'Enter a valid UPI ID, like 9876543210@upi.'
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppButton(
            label: subStrings['cancelConfirm']!,
            kind: AppButtonKind.danger,
            onPressed: _confirm,
          ),
        ],
      ),
    ),
  );
}

/// Prepaid top-up: shows the real UPI link and polls the plan until the
/// webhook flips `billing_status` to active. Closing early never claims
/// success — the plan card keeps the truthful pending state.
class _TopUpDialog extends StatefulWidget {
  const _TopUpDialog({
    required this.link,
    required this.reference,
    required this.amountPaise,
    required this.launched,
    required this.onCheck,
  });

  final String link;
  final String reference;
  final int? amountPaise;
  final bool launched;
  final Future<bool> Function() onCheck;

  @override
  State<_TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<_TopUpDialog> {
  bool _checking = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _poll();
    });
  }

  Future<void> _poll() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _notice = null;
    });
    for (var i = 0; i < 5; i++) {
      final active = await widget.onCheck();
      if (!mounted) return;
      if (active) {
        Navigator.of(context).pop(true);
        return;
      }
      if (i < 4) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _notice = subStrings['topupStillPending'];
    });
  }

  Future<void> _open() async {
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(widget.link),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _notice = ok ? null : subStrings['topupNoApp'];
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    if (!mounted) return;
    setState(() => _notice = subStrings['topupCopied']);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: ShodashaTheme.shape,
    title: Text(
      _checking
          ? subStrings['topupPendingTitle']!
          : subStrings['topupStarted']!,
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _checking
              ? subStrings['topupPendingBody']!
              : subStrings['topupBody']!,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        if (widget.amountPaise != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Amount', style: TextStyle(fontSize: 13)),
              Text(
                rupeesLabel(widget.amountPaise!),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: ShodashaTheme.ink,
                ),
              ),
            ],
          ),
        ],
        if (_checking) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ShodashaTheme.teal,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Checking for confirmation…',
                  style: TextStyle(fontSize: 12, color: ShodashaTheme.muted),
                ),
              ),
            ],
          ),
        ] else if (_notice != null) ...[
          const SizedBox(height: 10),
          Text(
            _notice!,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: ShodashaTheme.muted,
            ),
          ),
        ],
        if (widget.reference.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${subStrings['duesPayRef']}: ${widget.reference}',
            style: const TextStyle(fontSize: 12, color: ShodashaTheme.muted),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _copy,
        style: TextButton.styleFrom(foregroundColor: ShodashaTheme.blue),
        child: Text(subStrings['topupCopy']!),
      ),
      if (!widget.launched)
        TextButton(
          onPressed: _open,
          style: TextButton.styleFrom(foregroundColor: ShodashaTheme.blue),
          child: Text(subStrings['topupOpen']!),
        ),
      TextButton(
        onPressed: _checking ? null : _poll,
        style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
        child: Text(subStrings['topupCheck']!),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        style: TextButton.styleFrom(foregroundColor: ShodashaTheme.teal),
        child: Text(subStrings['topupDone']!),
      ),
    ],
  );
}
