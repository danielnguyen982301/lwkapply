import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_api.dart';

/// Logged-out "Forgot password?" screen, reached from LoginScreen.
/// Doesn't route through AuthController - same "no controller needed"
/// reasoning as ResetPasswordRequestScreen/DeleteAccountDialog: nothing
/// else in the app needs to observe this, so it calls authApiProvider
/// directly rather than mutating shared session state.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSubmitting = false;
  String? _submitError;
  bool _submitted = false;

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    if (!isValid) return;

    final email = (_formKey.currentState!.value['email'] as String).trim();
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await ref.read(authApiProvider).requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitted = true;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _submitted
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Check your email', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      "If an account exists for that email, we've sent a "
                      'link to reset your password.',
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Back to log in'),
                    ),
                  ],
                )
              : FormBuilder(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Enter your email and we'll send you a link to "
                        'reset your password.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
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
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      FormBuilderTextField(
                        name: 'email',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.email],
                        enabled: !_isSubmitting,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(
                            errorText: 'Email is required',
                          ),
                          FormBuilderValidators.email(
                            errorText: 'Enter a valid email',
                          ),
                        ]),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send reset link'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
