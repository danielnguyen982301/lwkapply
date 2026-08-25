import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/user_api.dart';

/// Shown via `showDialog` from SettingsScreen. Re-confirms the password
/// before the irreversible `DELETE /users/me` call — mobile counterpart
/// to webapp's `DeleteAccountDialog.vue`. No existing precedent for a
/// form-inside-a-dialog elsewhere in this app, but `AlertDialog` +
/// `FormBuilder` is consistent with both established conventions
/// (dialogs for confirmations, `flutter_form_builder` for input).
///
/// On success, `AuthController.deleteAccount` already clears the local
/// session and flips `AuthState` to unauthenticated — the router's own
/// `redirect` (see app/router.dart) reacts to that and sends the user to
/// `/login` on its own, same as a plain `logout()` already does, so this
/// dialog doesn't navigate anywhere itself.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    if (!isValid) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final password = _formKey.currentState!.value['password'] as String;
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(password: password);
      if (!mounted) return;
      Navigator.of(context).pop();
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
    return AlertDialog(
      title: const Text('Delete account'),
      content: FormBuilder(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently deletes your account, applications, '
              'documents, and everything else attached to it. '
              'This can\'t be undone.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            if (_submitError != null) ...[
              Text(
                _submitError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            FormBuilderTextField(
              name: 'password',
              obscureText: true,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm your password'),
              validator: FormBuilderValidators.required(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSubmitting ? null : _submit,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete my account'),
        ),
      ],
    );
  }
}
