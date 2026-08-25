import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_api.dart' show UserException;
import '../data/user_settings_api.dart';
import '../domain/user_settings.dart';

enum _LoadStatus { idle, loading, error }

const _defaultReminderLeadHours = 24;

/// Mobile counterpart to webapp's `NotificationSettingsCard.vue`. Local
/// widget state, not `flutter_form_builder` — same reasoning
/// `DocumentUploadSheet`'s doc comment gives for its own file-type
/// dropdown: no text/cross-field validation happening here that
/// form_builder would add value to, just booleans and one
/// already-range-clamped number.
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  _LoadStatus _loadStatus = _LoadStatus.loading;
  String? _loadError;

  bool _notificationsEnabled = true;
  bool _emailNotificationsEnabled = true;
  bool _pushNotificationsEnabled = true;
  bool _useCustomReminderLeadHours = false;
  final _reminderLeadHoursController = TextEditingController();

  bool _isSubmitting = false;
  String? _submitError;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reminderLeadHoursController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadStatus = _LoadStatus.loading;
      _loadError = null;
    });
    try {
      final settings = await ref.read(userSettingsApiProvider).fetch();
      if (!mounted) return;
      setState(() {
        _applySettings(settings);
        _loadStatus = _LoadStatus.idle;
      });
    } on UserException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadStatus = _LoadStatus.error;
        _loadError = e.message;
      });
    }
  }

  void _applySettings(UserSettings settings) {
    _notificationsEnabled = settings.notificationsEnabled;
    _emailNotificationsEnabled = settings.emailNotificationsEnabled;
    _pushNotificationsEnabled = settings.pushNotificationsEnabled;
    _useCustomReminderLeadHours = settings.reminderLeadHours != null;
    _reminderLeadHoursController.text =
        (settings.reminderLeadHours ?? _defaultReminderLeadHours).toString();
  }

  Future<void> _submit() async {
    int? reminderLeadHours;
    if (_useCustomReminderLeadHours) {
      final parsed = int.tryParse(_reminderLeadHoursController.text.trim());
      reminderLeadHours = (parsed == null) ? null : parsed.clamp(1, 168);
      if (reminderLeadHours != null) {
        _reminderLeadHoursController.text = reminderLeadHours.toString();
      }
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _saved = false;
    });
    try {
      final updated = await ref.read(userSettingsApiProvider).update(
            notificationsEnabled: _notificationsEnabled,
            emailNotificationsEnabled: _emailNotificationsEnabled,
            pushNotificationsEnabled: _pushNotificationsEnabled,
            reminderLeadHours:
                _useCustomReminderLeadHours ? reminderLeadHours : null,
          );
      if (!mounted) return;
      setState(() {
        _applySettings(updated);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: _buildBody(context),
      bottomNavigationBar: _loadStatus == _LoadStatus.idle
          ? SafeArea(
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
                    : const Text('Save preferences'),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadStatus == _LoadStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadStatus == _LoadStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError ?? 'Couldn\'t load your notification preferences.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return SingleChildScrollView(
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
          ] else if (_saved) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Preferences saved.',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notifications'),
            subtitle: const Text('Master switch for interview reminders.'),
            value: _notificationsEnabled,
            onChanged: (value) => setState(() => _notificationsEnabled = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Email'),
            subtitle: const Text('Send reminders by email.'),
            value: _emailNotificationsEnabled,
            onChanged: _notificationsEnabled
                ? (value) => setState(() => _emailNotificationsEnabled = value)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Push'),
            subtitle: const Text('Send reminders to your device.'),
            value: _pushNotificationsEnabled,
            onChanged: _notificationsEnabled
                ? (value) => setState(() => _pushNotificationsEnabled = value)
                : null,
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom reminder lead time'),
            subtitle: const Text(
              'How long before an interview to send the reminder. '
              'Default is $_defaultReminderLeadHours hours.',
            ),
            value: _useCustomReminderLeadHours,
            onChanged: (value) =>
                setState(() => _useCustomReminderLeadHours = value),
          ),
          if (_useCustomReminderLeadHours)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _reminderLeadHoursController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Reminder lead time (hours)',
                  helperText: '1–168 hours',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
