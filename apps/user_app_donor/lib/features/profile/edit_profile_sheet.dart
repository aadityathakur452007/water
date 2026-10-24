// S8 — Edit-profile bottom sheet (PATCH /v1/auth/me).
//
// States.md form coverage: default (prefilled), focused, filled, required/
// invalid (inline name + mobile + any-valid-email errors), submitting (button
// spinner, fields locked), submission failed (server message passthrough),
// success (sheet pops true; the caller confirms with a snackbar).
//
// Validation mirrors workers/api/src/app/services/auth_service.py:update_me
// (034: any valid email is accepted); the server remains the final gate and
// its message is shown verbatim.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_sheet.dart';
import 'profile_controller.dart';

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key, required this.controller});

  final ProfileController controller;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;

  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _serverError;
  bool _saving = false;
  String _initialName = '';
  String _initialPhone = '';
  String _initialEmail = '';

  bool get _dirty =>
      _nameCtrl.text.trim() != _initialName ||
      _phoneCtrl.text.trim() != _initialPhone ||
      _emailCtrl.text.trim() != _initialEmail;

  @override
  void initState() {
    super.initState();
    final user = widget.controller.user;
    _nameCtrl = TextEditingController(text: (user?['name'] ?? '') as String);
    _phoneCtrl = TextEditingController(text: (user?['phone'] ?? '') as String);
    _emailCtrl = TextEditingController(text: (user?['email'] ?? '') as String);
    _initialName = _nameCtrl.text.trim();
    _initialPhone = _phoneCtrl.text.trim();
    _initialEmail = _emailCtrl.text.trim();
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your unsaved profile changes will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, ShodashaTheme.minTarget),
              ),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: ShodashaTheme.danger,
                foregroundColor: ShodashaTheme.surface,
                minimumSize: const Size(48, ShodashaTheme.minTarget),
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = validateProfileName(_nameCtrl.text);
    final phoneError = validateProfilePhone(_phoneCtrl.text);
    final emailError = validateProfileEmail(_emailCtrl.text);
    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
      _emailError = emailError;
      _serverError = null;
    });
    if (nameError != null || phoneError != null || emailError != null) {
      return;
    }

    setState(() => _saving = true);
    final error = await widget.controller.updateProfile(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _serverError = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        await _requestClose();
      },
      child: AppSheet(
        title: 'Edit profile',
        onClose: _saving ? null : _requestClose,
        footer: AppButton(
          key: const Key('profile-save'),
          label: 'Save changes',
          busy: _saving,
          onPressed: _save,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Keep your contact details up to date for delivery updates.',
              style: TextStyle(
                fontSize: 14,
                color: ShodashaTheme.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('profile-name'),
              controller: _nameCtrl,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              decoration: InputDecoration(
                labelText: 'Your name',
                prefixIcon: const Icon(Icons.person_outline),
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('profile-phone'),
              controller: _phoneCtrl,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
              decoration: InputDecoration(
                labelText: 'Mobile number',
                hintText: '9876543210',
                helperText: '10 digits, starting 6–9',
                prefixIcon: const Icon(Icons.phone_outlined),
                errorText: _phoneError,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('profile-email'),
              controller: _emailCtrl,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _save();
              },
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              onChanged: (_) {
                if (_emailError != null) setState(() => _emailError = null);
              },
              decoration: InputDecoration(
                labelText: 'Email (optional)',
                hintText: 'you@example.com',
                helperText: 'Optional — used for receipts and updates.',
                prefixIcon: const Icon(Icons.email_outlined),
                errorText: _emailError,
              ),
            ),
            if (_serverError != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ServerError(message: _serverError!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Server/transport failure banner — the message is never swallowed.
class _ServerError extends StatelessWidget {
  const _ServerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShodashaTheme.surface,
        border: Border.all(color: ShodashaTheme.danger),
        borderRadius: BorderRadius.circular(ShodashaTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            size: 18,
            color: ShodashaTheme.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ShodashaTheme.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
