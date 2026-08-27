import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/wrapping_tab_selector.dart';
import '../../contacts/presentation/contacts_panel.dart';
import '../../documents/presentation/documents_panel.dart';
import '../../interviews/presentation/interviews_panel.dart';
import '../data/applications_api.dart';
import '../domain/application.dart';
import '../domain/application_draft.dart';
import 'application_form_result.dart';
import 'application_formatting.dart';

enum _LoadStatus { idle, loading, error }

/// Tab order for the editing view — index must match `_tabController`'s
/// `length` and the `WrappingTabSelector`/`TabBarView` children lists
/// below.
const _detailsTabIndex = 0;
const _tabLabels = ['Details', 'Contacts', 'Interviews', 'Documents'];

/// One shared form for both Create and Edit, following the same
/// "single component, two routes" shape as webapp's
/// ApplicationFormView.vue. `applicationId == null` means create.
///
/// When editing an existing application, this now mirrors
/// ApplicationFormView.vue's four-tab layout (Details / Contacts /
/// Interviews / Documents) rather than just the Details form: a
/// `TabController` drives a `WrappingTabSelector` (see that widget's doc
/// comment for why it's chips-in-a-`Wrap` rather than a `TabBar` — in
/// short, a fixed-width TabBar can't keep an arbitrary, growing number of
/// full-length labels both legible and fully visible on a phone screen)
/// plus a `TabBarView`, with Contacts/Interviews/Documents only reachable
/// once an application actually exists — same `!isNew && applicationId`
/// gating ContactsPanel.vue/InterviewsPanel.vue/DocumentsPanel.vue use
/// on web. A brand-new (not-yet-created) application only ever shows
/// the plain Details form, no tabs — there's nowhere to nest a contact,
/// interview, or document under an application that doesn't have an id
/// yet.
///
/// When editing, this screen fetches the application by id itself
/// (GET /applications/{id}) rather than trusting data passed in from
/// the list screen it was opened from — keeps the flow correct
/// regardless of how it was reached (a future deep link included), same
/// reasoning as ApplicationsApi.get's doc comment.
///
/// Uses flutter_form_builder + form_builder_validators throughout, per
/// MOBILE_SUMMARY.md's explicit note to use this same pattern for every
/// future form and not mix in bare TextFormField.
///
/// Submission/loading state is kept as local widget state rather than a
/// Riverpod controller — unlike ApplicationsListController, nothing
/// else needs to observe "is this form currently submitting," so a
/// StateNotifier would just be ceremony around what `setState` already
/// does plainly. Revisit only if some other screen needs to react to a
/// save in flight.
class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key, this.applicationId});

  final String? applicationId;

  bool get isEditing => applicationId != null;

  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormBuilderState>();

  // Only built when editing — a brand-new application has no tabs (see
  // the class doc comment above). Rebuilds the Scaffold's
  // bottomNavigationBar on every tab change, since "Save Changes" only
  // makes sense while on the Details tab; the other tabs manage their
  // own actions (e.g. ContactsPanel's own "Add contact" FAB).
  TabController? _tabController;

  _LoadStatus _loadStatus = _LoadStatus.idle;
  String? _loadError;
  Application? _existing;

  bool _isSubmitting = false;
  String? _submitError;

  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _tabController = TabController(length: 4, vsync: this)
        ..addListener(() {
          // Rebuilds so the bottomNavigationBar (Details-only) and the
          // AppBar's delete action reflect the newly active tab.
          // Fires during the swipe animation too, not just on a
          // completed change, which is fine here — setState is cheap
          // and every value it feeds into is read fresh from
          // _tabController.index at build time.
          if (mounted) setState(() {});
        });
      _loadExisting();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loadStatus = _LoadStatus.loading;
      _loadError = null;
    });
    try {
      final application =
          await ref.read(applicationsApiProvider).get(widget.applicationId!);
      if (!mounted) return;
      setState(() {
        _existing = application;
        _loadStatus = _LoadStatus.idle;
      });
    } on ApplicationsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadStatus = _LoadStatus.error;
        _loadError = e.message;
      });
    }
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.saveAndValidate() ?? false;
    if (!isValid) return;

    final values = _formKey.currentState!.value;
    final salaryMin = values['salaryMin'] as int?;
    final salaryMax = values['salaryMax'] as int?;

    // form_builder_validators has no built-in "compare to sibling field"
    // validator, so this cross-field check (mirroring the backend's
    // SalaryRangeValidationMixin) runs manually after saveAndValidate()
    // rather than inside either field's own `validator:` — reading the
    // *saved* value map here, not a live sibling lookup mid-validation,
    // avoids depending on field validation order.
    if (salaryMin != null && salaryMax != null && salaryMin > salaryMax) {
      _formKey.currentState?.fields['salaryMax']?.invalidate(
        'Must be \u2265 minimum salary',
      );
      return;
    }

    final draft = ApplicationDraft(
      company: values['company'] as String,
      position: values['position'] as String,
      applicationName: values['applicationName'] as String?,
      location: values['location'] as String?,
      status: values['status'] as ApplicationStatus,
      salaryMin: salaryMin,
      salaryMax: salaryMax,
      appliedDate: values['appliedDate'] as DateTime?,
      jobUrl: values['jobUrl'] as String?,
      notes: values['notes'] as String?,
    );

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final api = ref.read(applicationsApiProvider);
      final saved = widget.isEditing
          ? await api.update(widget.applicationId!, draft)
          : await api.create(draft);
      if (!mounted) return;
      context.pop(ApplicationSaved(saved));
    } on ApplicationsException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.message;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete application?'),
        content: Text(
          'This permanently deletes the ${_existing?.company ?? ''} '
          'application${_existing?.position != null ? ' (${_existing!.position})' : ''}. '
          'This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await ref.read(applicationsApiProvider).delete(widget.applicationId!);
      if (!mounted) return;
      context.pop(ApplicationDeleted(widget.applicationId!));
    } on ApplicationsException catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Wraps a validator so it's skipped on an empty/whitespace-only
  /// value — every optional text field on this form (location, job URL)
  /// should allow "leave it blank," not just "leave it untouched."
  ///
  /// Written explicitly rather than relying on form_builder_validators
  /// alone: v11.0.0 shipped a regression where some non-required fields
  /// started rejecting empty input (flutter-form-builder-ecosystem/
  /// form_builder_validators#116). This sidesteps that regardless of
  /// which patch version ends up resolved.
  FormFieldValidator<String> _optional(FormFieldValidator<String> inner) {
    return (value) {
      if (value == null || value.trim().isEmpty) return null;
      return inner(value);
    };
  }

  String? _emptyToNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  @override
  Widget build(BuildContext context) {
    final canShowForm = !widget.isEditing || _loadStatus == _LoadStatus.idle;
    final isOnDetailsTab =
        !widget.isEditing || _tabController?.index == _detailsTabIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Application' : 'New Application'),
        actions: [
          if (widget.isEditing && canShowForm)
            IconButton(
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Delete application',
              onPressed: _isDeleting ? null : _confirmDelete,
            ),
        ],
      ),
      body: _buildBody(),
      // "Save Changes"/"Add Application" only applies to the Details
      // tab — Contacts (and, later, Interviews/Documents) manage their
      // own actions (ContactsPanel's own "Add contact" FAB), so showing
      // a Details-specific save button over them would be misleading.
      bottomNavigationBar: (canShowForm && isOnDetailsTab)
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
                    : Text(
                        widget.isEditing ? 'Save Changes' : 'Add Application',
                      ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (widget.isEditing && _loadStatus == _LoadStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.isEditing && _loadStatus == _LoadStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError ?? 'Couldn\'t load this application.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadExisting,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.isEditing) {
      return Column(
        children: [
          WrappingTabSelector(
            labels: _tabLabels,
            selectedIndex: _tabController!.index,
            onSelected: (i) => _tabController!.animateTo(i),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDetailsForm(),
                ContactsPanel(applicationId: widget.applicationId!),
                InterviewsPanel(applicationId: widget.applicationId!),
                DocumentsPanel(applicationId: widget.applicationId!),
              ],
            ),
          ),
        ],
      );
    }

    return _buildDetailsForm();
  }

  Widget _buildDetailsForm() {
    return SingleChildScrollView(
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
              name: 'applicationName',
              initialValue: _existing?.applicationName,
              decoration: const InputDecoration(
                labelText: 'Application name',
                hintText: 'e.g. "Re-applied after rejection"',
              ),
              valueTransformer: _emptyToNull,
              validator: _optional(FormBuilderValidators.maxLength(255)),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'company',
              initialValue: _existing?.company,
              decoration: const InputDecoration(labelText: 'Company *'),
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(),
                FormBuilderValidators.maxLength(255),
              ]),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'position',
              initialValue: _existing?.position,
              decoration: const InputDecoration(labelText: 'Position *'),
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(),
                FormBuilderValidators.maxLength(255),
              ]),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'location',
              initialValue: _existing?.location,
              decoration: const InputDecoration(labelText: 'Location'),
              valueTransformer: _emptyToNull,
              validator: _optional(FormBuilderValidators.maxLength(255)),
            ),
            const SizedBox(height: 16),
            FormBuilderDropdown<ApplicationStatus>(
              name: 'status',
              initialValue: _existing?.status ?? ApplicationStatus.saved,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final status in ApplicationStatus.values)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FormBuilderTextField(
                    name: 'salaryMin',
                    initialValue: _existing?.salaryMin?.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Min salary',
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    valueTransformer: (text) =>
                        (text == null || text.trim().isEmpty)
                            ? null
                            : int.tryParse(text.trim()),
                    validator: _salaryValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FormBuilderTextField(
                    name: 'salaryMax',
                    initialValue: _existing?.salaryMax?.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Max salary',
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    valueTransformer: (text) =>
                        (text == null || text.trim().isEmpty)
                            ? null
                            : int.tryParse(text.trim()),
                    validator: _salaryValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormBuilderField<DateTime?>(
              name: 'appliedDate',
              initialValue: _existing?.appliedDate,
              builder: (field) {
                return InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: field.value ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) field.didChange(picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Applied date',
                      errorText: field.errorText,
                      suffixIcon: field.value == null
                          ? const Icon(Icons.calendar_today_outlined)
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => field.didChange(null),
                            ),
                    ),
                    child: Text(
                      field.value == null ? 'Not set' : formatDate(field.value),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'jobUrl',
              initialValue: _existing?.jobUrl,
              decoration: const InputDecoration(
                labelText: 'Job posting URL',
                hintText: 'https://…',
              ),
              keyboardType: TextInputType.url,
              valueTransformer: _emptyToNull,
              validator: _optional(FormBuilderValidators.maxLength(1000)),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'notes',
              initialValue: _existing?.notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
              valueTransformer: _emptyToNull,
              maxLines: 5,
              minLines: 3,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Backend's ApplicationBase constrains salary fields to `ge=0`
  /// integers (backend/app/schemas/application.py). Written as a plain
  /// function rather than composed form_builder_validators calls, since
  /// it needs both "is this a whole number" and "is it \u2265 0" in one
  /// pass, and int-parseability is simplest to just check directly.
  String? _salaryValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 0) return 'Enter 0 or greater';
    return null;
  }
}
