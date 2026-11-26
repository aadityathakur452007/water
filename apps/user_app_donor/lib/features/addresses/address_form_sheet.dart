part of 'address_screen.dart';

class _AddressFormSheet extends StatefulWidget {
  const _AddressFormSheet({required this.controller, this.existing});

  final AddressController controller;
  final AddressEntry? existing;

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  late final TextEditingController _house;
  late final TextEditingController _street;
  late final TextEditingController _pincode;
  late final TextEditingController _landmark;
  late final TextEditingController _customLabel;
  late final TextEditingController _phone;

  String _selectedTag = 'Home'; // 'Home', 'Work', 'Other'
  bool _lift = false;
  bool _touched = false;
  bool _busy = false;
  String? _saveError;
  _ServiceCheck _serviceState = _ServiceCheck.unchecked;

  final _houseFocus = FocusNode();
  final _streetFocus = FocusNode();
  final _pincodeFocus = FocusNode();

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _house = TextEditingController(text: e?.house ?? '');
    _street = TextEditingController(text: e?.street ?? e?.area ?? '');
    _pincode = TextEditingController(text: e?.pincode ?? '');
    _landmark = TextEditingController(text: e?.landmark ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _lift = e?.lift ?? false;

    if (e != null) {
      final lbl = e.label.trim();
      if (lbl == 'Home') {
        _selectedTag = 'Home';
        _customLabel = TextEditingController();
      } else if (lbl == 'Work' || e.type == AddrType.office) {
        _selectedTag = 'Work';
        _customLabel = TextEditingController();
      } else {
        _selectedTag = 'Other';
        _customLabel = TextEditingController(text: lbl);
      }
      _serviceState = _ServiceCheck.unknown;
    } else {
      // Pick next available tag slot
      final existingLabels =
          widget.controller.items.map((i) => i.label).toSet();
      if (!existingLabels.contains('Home')) {
        _selectedTag = 'Home';
      } else if (!existingLabels.contains('Work')) {
        _selectedTag = 'Work';
      } else {
        _selectedTag = 'Other';
      }
      _customLabel = TextEditingController();
    }
  }

  @override
  void dispose() {
    _house.dispose();
    _street.dispose();
    _pincode.dispose();
    _landmark.dispose();
    _customLabel.dispose();
    _phone.dispose();
    _houseFocus.dispose();
    _streetFocus.dispose();
    _pincodeFocus.dispose();
    super.dispose();
  }

  bool get _houseOk => _house.text.trim().isNotEmpty;
  bool get _streetOk => _street.text.trim().isNotEmpty;
  bool get _pinOk => isValidPincode(_pincode.text);
  bool get _phoneOk => isValidOptionalPhone(_phone.text);
  bool get _valid => _houseOk && _streetOk && _pinOk && _phoneOk;

  Future<void> _checkPincodeService(String pin) async {
    final clean = pin.trim();
    if (!isValidPincode(clean)) {
      if (_serviceState != _ServiceCheck.unchecked) {
        setState(() => _serviceState = _ServiceCheck.unchecked);
      }
      return;
    }
    setState(() => _serviceState = _ServiceCheck.checking);
    final serviceable = await widget.controller.checkServiceable(clean);
    if (!mounted) return;
    setState(() {
      _serviceState = serviceable == false
          ? _ServiceCheck.notServiceable
          : serviceable == true
              ? _ServiceCheck.serviceable
              : _ServiceCheck.unknown;
    });
  }

  Future<void> _save() async {
    setState(() {
      _touched = true;
      _saveError = null;
    });

    if (!_houseOk) {
      _houseFocus.requestFocus();
      return;
    }
    if (!_streetOk) {
      _streetFocus.requestFocus();
      return;
    }
    if (!_pinOk) {
      _pincodeFocus.requestFocus();
      return;
    }
    if (!_valid) return;

    setState(() => _busy = true);
    FocusScope.of(context).unfocus();

    final house = _house.text.trim();
    final street = _street.text.trim();
    final fullAddress = '$house, $street';
    final landmark = _landmark.text.trim().isEmpty ? null : _landmark.text.trim();
    final pincode = _pincode.text.trim();
    final phone = _phone.text.trim();

    String label = _selectedTag;
    if (_selectedTag == 'Other' && _customLabel.text.trim().isNotEmpty) {
      label = _customLabel.text.trim();
    }

    final entry = AddressEntry(
      id: widget.existing?.id ?? '',
      label: label,
      type: _selectedTag == 'Work' ? AddrType.office : AddrType.home,
      phone: phone,
      pincode: pincode,
      addressLine: fullAddress,
      house: house,
      street: street,
      area: street,
      landmark: landmark,
      lift: _lift,
      isDefault: widget.existing?.isDefault ?? false,
      lat: widget.existing?.lat ?? 23.2599,
      lng: widget.existing?.lng ?? 77.4126,
    );

    final ok = await widget.controller.save(entry, isNew: _isNew);
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saveError =
            widget.controller.errorMessage ?? addressStrings['server']!;
      });
    }
  }

  Widget _buildTagButton(String tag, IconData icon) {
    final selected = _selectedTag == tag;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTag = tag);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? ShodashaTheme.tealTint
                : ShodashaTheme.surface,
            border: Border.all(
              color: selected
                  ? ShodashaTheme.teal
                  : ShodashaTheme.border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? ShodashaTheme.teal
                    : ShodashaTheme.muted,
              ),
              const SizedBox(width: 6),
              Text(
                tag,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? ShodashaTheme.teal
                      : ShodashaTheme.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sheet Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: ShodashaTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isNew
                            ? addressStrings['addTitle']!
                            : addressStrings['editTitle']!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ShodashaTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Deliveries in India · Max 3 saved addresses',
                        style: TextStyle(
                          fontSize: 12,
                          color: ShodashaTheme.muted,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    color: ShodashaTheme.muted,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Deliver To Tag Selector
              const Text(
                'DELIVER TO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: ShodashaTheme.muted,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  _buildTagButton('Home', Icons.home_rounded),
                  const SizedBox(width: AppSpacing.sm),
                  _buildTagButton('Work', Icons.apartment_rounded),
                  const SizedBox(width: AppSpacing.sm),
                  _buildTagButton('Other', Icons.place_rounded),
                ],
              ),

              if (_selectedTag == 'Other') ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _customLabel,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Custom Label (e.g. Parents, Gym)',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(ShodashaTheme.radiusSm),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // House / Flat No.
              TextField(
                controller: _house,
                focusNode: _houseFocus,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  labelText: addressStrings['house'],
                  hintText: 'e.g. Flat 402, 4th Floor / House 12',
                  prefixIcon: const Icon(Icons.door_front_door_outlined, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  errorText: _touched && !_houseOk
                      ? addressStrings['errHouse']
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Apartment / Street / Locality
              TextField(
                controller: _street,
                focusNode: _streetFocus,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  labelText: addressStrings['addressLine'],
                  hintText: 'e.g. Royal Palms, Arera Colony',
                  prefixIcon: const Icon(Icons.location_city_outlined, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  errorText: _touched && !_streetOk
                      ? addressStrings['errLine']
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Pincode & Landmark Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: _pincode,
                      focusNode: _pincodeFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      maxLength: 6,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: addressStrings['pincode'],
                        hintText: 'e.g. 462016',
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ShodashaTheme.radiusSm),
                        ),
                        errorText: _touched && !_pinOk
                            ? addressStrings['errPincode']
                            : null,
                      ),
                      onChanged: (val) {
                        setState(() {});
                        _checkPincodeService(val);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _landmark,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: addressStrings['landmark'],
                        hintText: 'e.g. Opp. Apollo Pharmacy',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ShodashaTheme.radiusSm),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Serviceability feedback
              if (_serviceState == _ServiceCheck.checking)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        addressStrings['serviceChecking']!,
                        style: const TextStyle(
                            fontSize: 12, color: ShodashaTheme.muted),
                      ),
                    ],
                  ),
                ),
              if (_serviceState == _ServiceCheck.serviceable)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    addressStrings['serviceYes']!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ShodashaTheme.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (_serviceState == _ServiceCheck.notServiceable)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    addressStrings['serviceNo']!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ShodashaTheme.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: AppSpacing.sm),

              // Water Logistics: Lift Available Container
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 8),
                decoration: BoxDecoration(
                  color: ShodashaTheme.surface,
                  border: Border.all(color: ShodashaTheme.border),
                  borderRadius:
                      BorderRadius.circular(ShodashaTheme.radiusSm),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: ShodashaTheme.tealTint,
                        borderRadius:
                            BorderRadius.circular(ShodashaTheme.radiusSm),
                      ),
                      child: const Icon(
                        Icons.elevator_outlined,
                        size: 20,
                        color: ShodashaTheme.teal,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            addressStrings['lift']!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ShodashaTheme.ink,
                            ),
                          ),
                          Text(
                            addressStrings['liftHelper']!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: ShodashaTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _lift,
                      activeTrackColor: ShodashaTheme.teal,
                      onChanged: (v) => setState(() => _lift = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // Contact Phone
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  labelText: addressStrings['phone'],
                  hintText: 'Optional contact number for delivery rider',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ShodashaTheme.radiusSm),
                  ),
                  errorText: _touched && !_phoneOk
                      ? addressStrings['errPhone']
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),

              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _saveError!,
                    style: const TextStyle(
                      color: ShodashaTheme.danger,
                      fontSize: 13,
                    ),
                  ),
                ),

              const SizedBox(height: AppSpacing.lg),

              // Save CTA
              AppButton(
                label: _isNew
                    ? addressStrings['save']!
                    : addressStrings['update']!,
                kind: AppButtonKind.primary,
                height: 48,
                busy: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
