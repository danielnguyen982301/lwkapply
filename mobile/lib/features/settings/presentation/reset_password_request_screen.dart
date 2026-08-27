import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_api.dart';

/// Mobile counterpart to webapp's `PasswordSettingsCard.vue`. Doesn't
/// route through `AuthController` — unlike profile/avatar changes,
/// nothing else in the app needs to observe a password-reset request,
/// so this calls `userApiProvider` directly, same "no controller
/// needed" call ApplicationFormScreen's doc comment makes for local
/// form state.
class ResetPasswordRequestScreen extends ConsumerStatefulWidget {
  const ResetPasswordRequestScreen({super.key});

  @override
  ConsumerState<ResetPasswordRequestScreen> createState() =>
      _ResetPasswordRequestScreenState();
}

class _ResetPasswordRequestScreenState
    extends ConsumerState<ResetPasswordRequestScreen> {
  bool _isSubmitting = false;
  String? _submitError;
  bool _sent = false;

  Future<void> _requestReset() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _sent = false;
    });
    try {
      await ref.read(userApiProvider).requestPasswordReset();
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _sent = true;
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
      appBar: AppBar(title: const Text('Reset password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
            ] else if (_sent) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Check your email for a reset link.',
                  style:
                      TextStyle(color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text("We'll email you a link to set a new password."),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _isSubmitting ? null : _requestReset,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Reset password'),
        ),
      ),
    );
  }
}
