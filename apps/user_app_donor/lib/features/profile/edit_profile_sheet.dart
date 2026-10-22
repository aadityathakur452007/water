// S8 — Edit-profile bottom sheet (PATCH /v1/auth/me).
//
// States.md form coverage: default (prefilled), focused, filled, required/
// invalid (inline phone + @gmail.com errors), submitting (button spinner,
// fields locked), submission failed (server message passthrough), success
// (sheet pops true; the caller confirms with a snackbar).
//
// Validation mirrors workers/api/src/app/services/auth_service.py:update_me
// exactly; the server remains the final gate (its message is shown verbatim).

import 'package:flutter/material.dart';

import '../../core/theme.dart';
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

  String? _phoneError;
  String? _emailError;
  String? _serverError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.controller.user;
    _nameCtrl = TextEditingController(text: (user?['name'] ?? '') as String);
    _phoneCtrl = TextEditingController(text: (user?['phone'] ?? '') as String);
    _emailCtrl = TextEditingController(text: (user?['email'] ?? '') as String);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phoneError = validateProfilePhone(_phoneCtrl.text);
    final emailError = validateProfileEmail(_emailCtrl.text);
    setState(() {
      _phoneError = phoneError;
      _emailError = emailError;
      _serverError = null;
    });
    if (phoneError != null || emailError != null) return;

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
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Edit profile',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: ShodashaTheme.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, color: ShodashaTheme.muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Keep your contact details up to date for delivery updates.',
              style: TextStyle(
                fontSize: 13,
                color: ShodashaTheme.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('profile-name'),
              controller: _nameCtrl,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 16, color: ShodashaTheme.ink),
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
                labelText: 'Gmail address',
                hintText: 'you@gmail.com',
                prefixIcon: const Icon(Icons.email_outlined),
                errorText: _emailError,
              ),
            ),
            if (_serverError != null) ...[
              const SizedBox(height: 12),
              _ServerError(message: _serverError!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('profile-save'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: ShodashaTheme.teal,
                  foregroundColor: ShodashaTheme.surface,
                  disabledBackgroundColor: ShodashaTheme.teal.withValues(
                    alpha: 0.4,
                  ),
                  minimumSize: const Size.fromHeight(52),
                  shape: ShodashaTheme.shape,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ShodashaTheme.surface,
                        ),
                      )
                    : const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared sheet drag handle (donor checkout chrome, no image assets).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: ShodashaTheme.border,
          borderRadius: BorderRadius.circular(2),
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
