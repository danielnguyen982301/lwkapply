import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

import '../domain/interview.dart';
import '../domain/interview_draft.dart';
import 'interview_formatting.dart';

/// Add/edit form for a single interview, shown via
/// `showModalBottomSheet` from InterviewsPanel — same shape as
/// ContactFormSheet, plus the extra fields Interview needs (type,
/// scheduled date & time, duration, result).
///
/// `scheduled_at` uses the same `FormBuilderField<DateTime?>` +
/// `showDatePicker` pattern as ApplicationFormScreen's `appliedDate`
/// field (features/applications/presentation/application_form_screen.dart),
/// extended with a second `showTimePicker` call — there's no
/// `intl`/date-picker package dependency to lean on (see
/// application_formatting.dart's doc comment), and the web's single
/// PrimeVue `DatePicker` with `show-time` doesn't have a stock Flutter
/// equivalent worth pulling in a new package for just this one field.
class InterviewFormSheet extends StatefulWidget {
  const InterviewFormSheet({
    super.key,
    this.existing,
    required this.onSubmit,
  });

  final Interview? existing;

  /// Performs the actual create/update API call. Rethrows
  /// InterviewsException on failure so the sheet can show it inline;
  /// returns nothing on success, at which point the sheet closes itself.
  final Future<void> Function(InterviewDraft draft) onSubmit;

  @override
  State<InterviewFormSheet> createState() => _InterviewFormSheetState();
}

class _InterviewFormSheetState extends State<InterviewFormSheet> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSubmitting = false;
  String? _submitError;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    if (!isValid) return;

    final values = _formKey.currentState!.value;
    final draft = InterviewDraft(
      type: values['type'] as InterviewType,
      scheduledAt: values['scheduledAt'] as DateTime,
      durationMinutes:
          (values['durationMinutes'] as String?)?.trim().isEmpty ?? true
              ? null
              : int.tryParse((values['durationMinutes'] as String).trim()),
      feedback: _emptyToNull(values['feedback'] as String?),
      result: values['result'] as InterviewResult,
    );

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onSubmit(draft);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString();
      });
    }
  }

  String? _emptyToNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Same "skip validation on blank optional field" wrapper as
  /// ApplicationFormScreen._optional/ContactFormSheet._optional.
  FormFieldValidator<String> _optional(FormFieldValidator<String> inner) {
    return (value) {
      if (value == null || value.trim().isEmpty) return null;
      return inner(value);
    };
  }

  @override
  Widget build(BuildContext context) {
    // scheduled_at is stored as UTC (see Interview.scheduledAt's doc
    // comment) — convert to local once here so both the picker's
    // initial value and the display text are in the device's timezone.
    final initialScheduledAt = widget.existing?.scheduledAt.toLocal();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FormBuilder(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit interview' : 'Add interview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_submitError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _submitError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                FormBuilderDropdown<InterviewType>(
                  name: 'type',
                  initialValue:
                      widget.existing?.type ?? InterviewType.phoneScreen,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final type in InterviewType.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                ),
                const SizedBox(height: 16),
                FormBuilderField<DateTime?>(
                  name: 'scheduledAt',
                  initialValue: initialScheduledAt,
                  validator: (value) =>
                      value == null ? 'Pick a date and time' : null,
                  builder: (field) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final now = DateTime.now();
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: field.value ?? now,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (pickedDate == null) return;
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: field.value != null
                              ? TimeOfDay.fromDateTime(field.value!)
                              : TimeOfDay.fromDateTime(now),
                        );
                        if (pickedTime == null) return;
                        field.didChange(
                          DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          ),
                        );
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date & time *',
                          errorText: field.errorText,
                          suffixIcon: field.value == null
                              ? const Icon(Icons.event_outlined)
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => field.didChange(null),
                                ),
                        ),
                        child: Text(
                          field.value == null
                              ? 'Not set'
                              : formatDateTime(field.value!),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                FormBuilderTextField(
                  name: 'durationMinutes',
                  initialValue: widget.existing?.durationMinutes?.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (minutes)',
                  ),
                  validator: _optional(_durationValidator),
                ),
                const SizedBox(height: 16),
                FormBuilderDropdown<InterviewResult>(
                  name: 'result',
                  initialValue:
                      widget.existing?.result ?? InterviewResult.pending,
                  decoration: const InputDecoration(labelText: 'Result'),
                  items: [
                    for (final result in InterviewResult.values)
                      DropdownMenuItem(
                        value: result,
                        child: Text(result.label),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FormBuilderTextField(
                  name: 'feedback',
                  initialValue: widget.existing?.feedback,
                  decoration: const InputDecoration(
                    labelText: 'Feedback',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  minLines: 2,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
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
                            : Text(
                                _isEditing ? 'Save changes' : 'Add interview',
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Backend constrains `duration_minutes` to `ge=1, le=1440`
  /// (backend/app/schemas/interview.py) — same "whole number + range"
  /// shape as ApplicationFormScreen._salaryValidator, bounds adjusted.
  String? _durationValidator(String? value) {
    final parsed = int.tryParse(value!.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 1 || parsed > 1440) return 'Enter 1–1440';
    return null;
  }
}
