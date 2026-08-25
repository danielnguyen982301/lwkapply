import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../../../core/utils/timezone.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/session_providers.dart';
import '../data/user_api.dart' show UserException;
import 'timezone_picker_sheet.dart';

/// Mobile counterpart to webapp's `ProfileSettingsCard.vue` — avatar,
/// first/last name, and a timezone override, all landing on
/// `AuthController` so `currentUserProvider` (and this screen's own
/// `ref.watch`) update immediately after a save.
///
/// Submission state is local widget state, not a Riverpod controller,
/// same reasoning ApplicationFormScreen's doc comment gives: nothing
/// else needs to observe "is this form currently submitting."
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormBuilderState>();

  bool _isSubmitting = false;
  String? _submitError;
  bool _saved = false;

  bool _avatarBusy = false;
  String? _avatarError;

  // Timezone is plain state, not part of the FormBuilder above - it's
  // nullable (auto-detect off + nothing picked yet isn't itself a form
  // "value"), and only gets sent when actually changed from what's
  // saved (see _timezoneDirty/_submit), same reasoning
  // ProfileSettingsCard.vue keeps this out of its own vee-validate form.
  late bool _autoDetectTimezone;
  String? _selectedTimezone;
  late bool _savedAutoDetectTimezone;
  late String? _savedTimezone;
  String? _timezoneError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider)!;
    _autoDetectTimezone = !user.timezoneIsManual;
    _selectedTimezone = user.timezone;
    _savedAutoDetectTimezone = _autoDetectTimezone;
    _savedTimezone = user.timezone;
  }

  bool get _timezoneDirty =>
      _autoDetectTimezone != _savedAutoDetectTimezone ||
      (!_autoDetectTimezone && _selectedTimezone != _savedTimezone);

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // Matches the backend's accepted avatar content types
      // (AVATAR_ALLOWED_CONTENT_TYPES in app/services/r2.py) — a UI-level
      // filter only, the server still validates for real.
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = result?.files.isNotEmpty == true ? result!.files.single : null;
    if (file == null || file.path == null) return;

    setState(() {
      _avatarBusy = true;
      _avatarError = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .uploadAvatar(filePath: file.path!, fileName: file.name);
    } on UserException catch (e) {
      if (!mounted) return;
      setState(() => _avatarError = e.message);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text('This removes your profile photo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _avatarBusy = true;
      _avatarError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).removeAvatar();
    } on UserException catch (e) {
      if (!mounted) return;
      setState(() => _avatarError = e.message);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _pickTimezone() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          TimezonePickerSheet(initialValue: _selectedTimezone),
    );
    if (selected == null) return;
    setState(() {
      _selectedTimezone = selected;
      _timezoneError = null;
    });
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    final timezoneValid = _autoDetectTimezone || _selectedTimezone != null;
    setState(() {
      _timezoneError = timezoneValid
          ? null
          : 'Choose a timezone, or turn auto-detect back on.';
    });
    if (!isValid || !timezoneValid) return;

    final values = _formKey.currentState!.value;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _saved = false;
    });
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            firstName: values['firstName'] as String,
            lastName: values['lastName'] as String,
            includeTimezone: _timezoneDirty,
            timezone: _autoDetectTimezone ? null : _selectedTimezone,
          );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _saved = true;
        _savedAutoDetectTimezone = _autoDetectTimezone;
        _savedTimezone = _selectedTimezone;
      });
    } on UserException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.message;
      });
    }
  }

  String get _timezoneSubtitle {
    if (_selectedTimezone == null) return 'Not set';
    final match = timezoneOptions().where((o) => o.value == _selectedTimezone);
    return match.isEmpty ? _selectedTimezone! : match.first.label;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final theme = Theme.of(context);
    final initials = '${user.firstName.isNotEmpty ? user.firstName[0] : ''}'
            '${user.lastName.isNotEmpty ? user.lastName[0] : ''}'
        .toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: user.avatarUrl != null
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            initials.isEmpty ? '?' : initials,
                            style: theme.textTheme.headlineMedium,
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _avatarBusy ? null : _pickAvatar,
                        child: _avatarBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Change photo'),
                      ),
                      if (user.avatarUrl != null)
                        TextButton(
                          onPressed: _avatarBusy ? null : _removeAvatar,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                  if (_avatarError != null)
                    Text(
                      _avatarError!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FormBuilder(
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
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
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
                        'Profile updated.',
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FormBuilderTextField(
                    name: 'firstName',
                    initialValue: user.firstName,
                    decoration:
                        const InputDecoration(labelText: 'First name *'),
                    validator: FormBuilderValidators.compose([
                      FormBuilderValidators.required(),
                      FormBuilderValidators.maxLength(100),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  FormBuilderTextField(
                    name: 'lastName',
                    initialValue: user.lastName,
                    decoration: const InputDecoration(labelText: 'Last name *'),
                    validator: FormBuilderValidators.compose([
                      FormBuilderValidators.required(),
                      FormBuilderValidators.maxLength(100),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: user.email,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-detect timezone'),
                    subtitle: const Text(
                      'Kept in sync with your device on login — used to '
                      'localize interview reminder times.',
                    ),
                    value: _autoDetectTimezone,
                    onChanged: (value) =>
                        setState(() => _autoDetectTimezone = value),
                  ),
                  if (!_autoDetectTimezone)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Choose your own timezone'),
                      subtitle: Text(_timezoneSubtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickTimezone,
                    ),
                  if (_timezoneError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _timezoneError!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
              : const Text('Save'),
        ),
      ),
    );
  }
}
