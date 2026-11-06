import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../auth/domain/auth_validators.dart';
import '../../auth/widgets/password_field.dart';

/// Profile menu -> Change password. Resolves to true when it was changed.
///
/// Its own flow, away from the everyday profile form, and it asks for the
/// current password first - the usual account-security pattern.
Future<bool> showChangePasswordSheet(BuildContext context) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const ChangePasswordSheet(),
  );
  return changed ?? false;
}

class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet({super.key});

  @override
  ConsumerState<ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is AuthFailure
            ? error.message
            : 'Could not change your password. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Change password',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Confirm your current password, then choose a new one.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    PasswordField(
                      controller: _current,
                      label: 'Current password',
                      obscured: _hideCurrent,
                      onToggleObscured: () =>
                          setState(() => _hideCurrent = !_hideCurrent),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your current password.'
                          : null,
                      autofillHints: const [AutofillHints.password],
                      enabled: !_saving,
                    ),
                    const SizedBox(height: 16),
                    PasswordField(
                      controller: _new,
                      label: 'New password',
                      obscured: _hideNew,
                      onToggleObscured: () =>
                          setState(() => _hideNew = !_hideNew),
                      validator: (v) {
                        final problem = AuthValidators.password(v);
                        if (problem != null) return problem;
                        return v == _current.text
                            ? 'Pick a password you are not using now.'
                            : null;
                      },
                      autofillHints: const [AutofillHints.newPassword],
                      enabled: !_saving,
                    ),
                    const SizedBox(height: 16),
                    PasswordField(
                      controller: _confirm,
                      label: 'Confirm new password',
                      obscured: _hideConfirm,
                      onToggleObscured: () =>
                          setState(() => _hideConfirm = !_hideConfirm),
                      validator: (v) =>
                          AuthValidators.confirmPassword(v, _new.text),
                      autofillHints: const [AutofillHints.newPassword],
                      enabled: !_saving,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Update password'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
