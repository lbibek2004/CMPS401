import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lionfit/core/auth/auth_controller.dart';
import 'package:lionfit/core/router/app_router.dart';

import 'domain/auth_validators.dart';
import 'widgets/auth_form_shell.dart';
import 'widgets/auth_notice.dart';
import 'widgets/password_field.dart';
import 'widgets/submit_button.dart';

/// Create an account: display name, email, password, confirmation.
///
/// Keep the class name and the const constructor: `core/router/app_router.dart`
/// references both.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  AuthFailure? _failure;

  /// Set when Supabase accepted the sign-up but issued no session, which only
  /// happens when "Confirm email" is still on. Not an error - the account was
  /// created - but the user is stuck all the same.
  bool _awaitingConfirmation = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _clearNotice() {
    if (_failure != null || _awaitingConfirmation) {
      setState(() {
        _failure = null;
        _awaitingConfirmation = false;
      });
    }
  }

  Future<void> _submit() async {
    // Belt and braces with the disabled button: the keyboard "done" action can
    // also land here.
    if (_submitting) return;

    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _failure = null;
      _awaitingConfirmation = false;
    });

    try {
      await ref
          .read(authControllerProvider)
          .signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            displayName: _nameController.text.trim(),
          );

      if (!mounted) return;

      // Sign-up succeeds in two different shapes. With confirmation off there
      // is a session, the router sees it and redirects - do nothing here, and
      // keep the form locked until this screen is replaced. With confirmation
      // on there is no session and no error, so without this branch the screen
      // would just sit there looking broken.
      if (ref.read(isSignedInProvider)) return;

      setState(() {
        _submitting = false;
        _awaitingConfirmation = true;
      });
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;

    return AuthFormShell(
      title: 'Create your account',
      subtitle: 'Plan your week around the Pennington Rec Center and track every set.',
      footerPrompt: 'Already have an account?',
      footerAction: 'Sign in',
      footerRoute: Routes.login,
      form: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                focusNode: _nameFocus,
                enabled: !_submitting,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: AuthValidators.displayName,
                onChanged: (_) => _clearNotice(),
                onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'Pao',
                  helperText:
                      'What LionFit calls you. You can change it later.',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperMaxLines: 2,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocus,
                enabled: !_submitting,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: AuthValidators.email,
                onChanged: (_) => _clearNotice(),
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@selu.edu',
                  prefixIcon: Icon(Icons.alternate_email),
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                label: 'Password',
                enabled: !_submitting,
                obscured: _obscurePassword,
                onToggleObscured: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                helperText:
                    'At least ${AuthValidators.minPasswordLength} characters.',
                validator: AuthValidators.password,
                onChanged: (_) => _clearNotice(),
                onSubmitted: (_) => _confirmFocus.requestFocus(),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirmController,
                focusNode: _confirmFocus,
                label: 'Confirm password',
                enabled: !_submitting,
                obscured: _obscureConfirm,
                onToggleObscured: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                validator: (value) => AuthValidators.confirmPassword(
                  value,
                  _passwordController.text,
                ),
                onChanged: (_) => _clearNotice(),
                onSubmitted: (_) => unawaited(_submit()),
              ),
              if (notice != null) ...[const SizedBox(height: 16), notice],
              const SizedBox(height: 24),
              SubmitButton(
                label: 'Create account',
                busyLabel: 'Creating account...',
                busy: _submitting,
                onPressed: () => unawaited(_submit()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The inline block above the submit button: either the stuck-on-confirmation
  /// explainer or the server's own message.
  Widget? get _notice {
    if (_awaitingConfirmation) {
      return AuthNotice.unconfirmedEmail(
        tone: AuthNoticeTone.caution,
        title: 'Account created - but it cannot sign in yet',
        message:
            'Supabase accepted the sign-up and then stopped at email '
            'confirmation, so there is no session yet and nothing to open.',
      );
    }

    final failure = _failure;
    if (failure == null) return null;

    if (failure.isUnconfirmedEmail) {
      return AuthNotice.unconfirmedEmail(
        title: 'That account exists but has not confirmed its email',
        message: failure.message,
      );
    }
    return AuthNotice(
      title: 'Could not create the account',
      message: failure.message,
    );
  }
}
