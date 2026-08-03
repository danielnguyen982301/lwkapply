import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../domain/contact.dart';
import '../domain/contact_draft.dart';

/// Add/edit form for a single contact, shown via `showModalBottomSheet`
/// from ContactsPanel — the mobile equivalent of ContactsPanel.vue's
/// PrimeVue `Dialog`. `existing == null` means "add"; otherwise "edit".
///
/// Kept as its own widget (rather than inlined in ContactsPanel) so the
/// sheet can manage its own form/submit state independently of the
/// panel's list state, same separation ApplicationFormScreen keeps
/// between form fields and submit/delete state.
class ContactFormSheet extends StatefulWidget {
  const ContactFormSheet({super.key, this.existing, required this.onSubmit});

  final Contact? existing;

  /// Performs the actual create/update API call. Rethrows
  /// ContactsException on failure so the sheet can show it inline;
  /// returns nothing on success, at which point the sheet closes itself.
  final Future<void> Function(ContactDraft draft) onSubmit;

  @override
  State<ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends State<ContactFormSheet> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isSubmitting = false;
  String? _submitError;

  bool get _isEditing => widget.existing != null;

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    if (!isValid) return;

    final values = _formKey.currentState!.value;
    final draft = ContactDraft(
      name: (values['name'] as String).trim(),
      title: _emptyToNull(values['title'] as String?),
      email: _emptyToNull(values['email'] as String?),
      linkedinUrl: _emptyToNull(values['linkedinUrl'] as String?),
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
  /// ApplicationFormScreen._optional — title and LinkedIn URL are
  /// optional, only email needs format validation when non-empty.
  FormFieldValidator<String> _optional(FormFieldValidator<String> inner) {
    return (value) {
      if (value == null || value.trim().isEmpty) return null;
      return inner(value);
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet above the keyboard so the field being edited
      // stays visible.
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
                  _isEditing ? 'Edit contact' : 'Add contact',
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
                FormBuilderTextField(
                  name: 'name',
                  initialValue: widget.existing?.name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    FormBuilderValidators.maxLength(255),
                  ]),
                ),
                const SizedBox(height: 16),
                FormBuilderTextField(
                  name: 'title',
                  initialValue: widget.existing?.title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: _optional(FormBuilderValidators.maxLength(255)),
                ),
                const SizedBox(height: 16),
                FormBuilderTextField(
                  name: 'email',
                  initialValue: widget.existing?.email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: _optional(FormBuilderValidators.email()),
                ),
                const SizedBox(height: 16),
                FormBuilderTextField(
                  name: 'linkedinUrl',
                  initialValue: widget.existing?.linkedinUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'LinkedIn URL',
                    hintText: 'https://linkedin.com/in/…',
                  ),
                  validator: _optional(FormBuilderValidators.maxLength(500)),
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
                            : Text(_isEditing ? 'Save changes' : 'Add contact'),
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
}
