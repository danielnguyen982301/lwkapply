import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../applications/data/applications_api.dart';
import '../../applications/domain/application.dart';

/// Search-and-pick-one widget for choosing a tracked `Application` whose
/// `job_url` should drive ATS Score's job-description sourcing. Same
/// shape as ResumeDocumentPicker — see that file's doc comment for the
/// full "why a plain debounced TextField, why call the stateless API
/// directly" reasoning, which applies identically here.
class ApplicationPicker extends ConsumerStatefulWidget {
  const ApplicationPicker({super.key, required this.onSelected});

  final ValueChanged<Application> onSelected;

  @override
  ConsumerState<ApplicationPicker> createState() => _ApplicationPickerState();
}

class _ApplicationPickerState extends ConsumerState<ApplicationPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Application> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final response = await ref
          .read(applicationsApiProvider)
          .list(search: query, pageSize: 10);
      if (!mounted) return;
      setState(() => _results = response.items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Application application) {
    setState(() {
      _results = [];
      _controller.text = _hasApplicationName(application)
          ? application.applicationName!
          : application.company;
    });
    FocusScope.of(context).unfocus();
    widget.onSelected(application);
  }

  bool _hasApplicationName(Application application) {
    return application.applicationName?.isNotEmpty == true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Application',
            hintText: 'Search your tracked applications…',
            border: const OutlineInputBorder(),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _onChanged,
        ),
        if (_results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final application = _results[index];
                final hasJobUrl = application.jobUrl != null &&
                    application.jobUrl!.isNotEmpty;
                return ListTile(
                  dense: true,
                  title: Text(
                    _hasApplicationName(application)
                        ? application.applicationName!
                        : application.company,
                  ),
                  subtitle: Text(
                    _hasApplicationName(application)
                        ? '${application.company} · ${application.position}'
                        : application.position,
                  ),
                  // job_url drives ATS Score's auto-fetch path (see
                  // AtsScoresTab's create sheet) — surfacing it here up
                  // front avoids a later "no job_url" 422 surprise,
                  // mirroring ApplicationPicker.vue's Tag hint.
                  trailing: Chip(
                    label: Text(hasJobUrl ? 'Has job URL' : 'No job URL'),
                    backgroundColor: hasJobUrl
                        ? Colors.green.shade50
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: hasJobUrl
                          ? Colors.green.shade800
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onTap: () => _select(application),
                );
              },
            ),
          ),
      ],
    );
  }
}
