import 'package:flutter/material.dart';

/// A password input with a visibility toggle, used three times across the two
/// auth screens (sign in, sign up, confirm).
class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.obscured,
    required this.onToggleObscured,
    required this.validator,
    required this.autofillHints,
    required this.enabled,
    this.focusNode,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final bool obscured;
  final VoidCallback onToggleObscured;
  final FormFieldValidator<String> validator;

  /// [AutofillHints.password] when signing in, [AutofillHints.newPassword]
  /// when creating an account - the browser treats them very differently.
  final List<String> autofillHints;

  /// False while a request is in flight, so the form cannot be edited midway
  /// through a submit.
  final bool enabled;

  final FocusNode? focusNode;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscured,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        errorMaxLines: 2,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: onToggleObscured,
          tooltip: obscured ? 'Show password' : 'Hide password',
          icon: Icon(
            obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}
