import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lionfit/core/auth/auth_controller.dart';
import 'package:lionfit/core/router/routes.dart';

import 'domain/auth_validators.dart';
import 'widgets/auth_form_shell.dart';
import 'widgets/auth_notice.dart';
import 'widgets/password_field.dart';
import 'widgets/submit_button.dart';

/// Email + password sign-in.
///
/// Keep the class name and the const constructor: `core/router/app_router.dart`
/// references both.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _submitting = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// A server error describes the values that were sent. The moment the user
  /// edits one, it is stale - drop it rather than leave it contradicting the
  /// field under it.
  void _clearFailure() {
    if (_failure != null) setState(() => _failure = null);
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
    });

    try {
      await ref
          .read(authControllerProvider)
          .signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      if (!mounted) return;

      // No context.go() on success, on purpose: the router listens to auth
      // state and redirects on its own, so navigating here would do it twice.
      // Leaving _submitting true keeps the form locked for the handful of
      // frames before this screen is replaced.
      if (ref.read(isSignedInProvider)) return;

      // Belt and braces: a "success" with no session would otherwise strand
      // the user on a form that spins forever.
      setState(() => _submitting = false);
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
    return AuthFormShell(
      title: 'Welcome back',
      subtitle: 'Sign in to pick up your plan where you left off.',
      footerPrompt: 'New to LionFit?',
      footerAction: 'Create an account',
      footerRoute: Routes.signUp,
      form: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocus,
                enabled: !_submitting,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                validator: AuthValidators.email,
                onChanged: (_) => _clearFailure(),
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
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                validator: AuthValidators.password,
                onChanged: (_) => _clearFailure(),
                onSubmitted: (_) => unawaited(_submit()),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 16),
                _failureNotice(_failure!),
              ],
              const SizedBox(height: 24),
              SubmitButton(
                label: 'Sign in',
                busyLabel: 'Signing in...',
                busy: _submitting,
                onPressed: () => unawaited(_submit()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _failureNotice(AuthFailure failure) {
    // The one failure worth more than a sentence: the account exists, the
    // password is right, and nothing the user types will help.
    if (failure.isUnconfirmedEmail) {
      return AuthNotice.unconfirmedEmail(
        title: 'This account has not confirmed its email',
        message: failure.message,
      );
    }
    return AuthNotice(title: 'Could not sign in', message: failure.message);
  }
}
