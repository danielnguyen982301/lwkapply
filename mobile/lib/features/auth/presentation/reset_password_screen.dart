import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_api.dart';

/// Reached either by tapping the emailed password-reset link (handed
/// off by DeepLinkService via the Android intent-filter in
/// AndroidManifest.xml) or, if `token` is missing/malformed, still
/// routed here by go_router (see router.dart) so there's a single place
/// that explains the link didn't work.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSubmitting = false;
  String? _submitError;
  bool _succeeded = false;

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    if (!isValid) return;

    final values = _formKey.currentState!.value;
    final newPassword = values['newPassword'] as String;
    final confirmPassword = values['confirmPassword'] as String;
    if (newPassword != confirmPassword) {
      _formKey.currentState?.fields['confirmPassword']?.invalidate(
        "Passwords don't match.",
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await ref.read(authApiProvider).confirmPasswordReset(
            token: widget.token!,
            newPassword: newPassword,
          );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _succeeded = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.token == null || widget.token!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Invalid link', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('This password reset link is missing or malformed.'),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => context.go('/forgot-password'),
                  child: const Text('Request a new link'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_succeeded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Password reset', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Your password has been changed. You can now log in.',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Log in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FormBuilder(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_submitError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _submitError!,
                      style:
                          TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                FormBuilderTextField(
                  name: 'newPassword',
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 8 characters.',
                    border: OutlineInputBorder(),
                  ),
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    FormBuilderValidators.minLength(8),
                    FormBuilderValidators.maxLength(128),
                  ]),
                ),
                const SizedBox(height: 16),
                FormBuilderTextField(
                  name: 'confirmPassword',
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    border: OutlineInputBorder(),
                  ),
                  validator: FormBuilderValidators.required(),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reset password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
