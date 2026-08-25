import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../data/user_api.dart';

/// Mobile counterpart to webapp's `PasswordSettingsCard.vue`. Doesn't
/// route through `AuthController` — unlike profile/avatar changes,
/// nothing else in the app needs to observe a password change, so this
/// calls `userApiProvider` directly, same "no controller needed" call
/// ApplicationFormScreen's doc comment makes for local form state.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSubmitting = false;
  String? _submitError;
  bool _saved = false;

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    if (!isValid) return;

    final values = _formKey.currentState!.value;
    final newPassword = values['newPassword'] as String;
    final confirmPassword = values['confirmPassword'] as String;
    if (newPassword != confirmPassword) {
      _formKey.currentState?.fields['confirmPassword']?.invalidate(
        'Passwords don\'t match.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _saved = false;
    });
    try {
      await ref.read(userApiProvider).changePassword(
            currentPassword: values['currentPassword'] as String,
            newPassword: newPassword,
          );
      if (!mounted) return;
      _formKey.currentState?.reset();
      setState(() {
        _isSubmitting = false;
        _saved = true;
      });
    } on UserException catch (e) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FormBuilder(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (_saved) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Password changed.',
                    style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FormBuilderTextField(
                name: 'currentPassword',
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current password *'),
                validator: FormBuilderValidators.required(),
              ),
              const SizedBox(height: 16),
              FormBuilderTextField(
                name: 'newPassword',
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password *',
                  helperText: 'At least 8 characters.',
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
                decoration:
                    const InputDecoration(labelText: 'Confirm new password *'),
                validator: FormBuilderValidators.required(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Change password'),
        ),
      ),
    );
  }
}
