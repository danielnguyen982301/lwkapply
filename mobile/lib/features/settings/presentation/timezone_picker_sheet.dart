import 'package:flutter/material.dart';

import '../../../core/utils/timezone.dart';

/// Searchable timezone picker, shown via `showModalBottomSheet<String>`
/// from ProfileScreen. No searchable-`Select` precedent exists elsewhere
/// in this app (`DropdownButtonFormField`/`FormBuilderDropdown` don't
/// support in-place filtering) — this is a purpose-built local filter
/// over `timezoneOptions()`'s static ~400-entry list, not a remote
/// debounced search like `ResumeDocumentPicker`'s/`ApplicationPicker`'s
/// (there's no backend endpoint to search here).
class TimezonePickerSheet extends StatefulWidget {
  const TimezonePickerSheet({super.key, this.initialValue});

  final String? initialValue;

  @override
  State<TimezonePickerSheet> createState() => _TimezonePickerSheetState();
}

class _TimezonePickerSheetState extends State<TimezonePickerSheet> {
  final _searchController = TextEditingController();
  late final List<TimezoneOption> _allOptions = timezoneOptions();
  late List<TimezoneOption> _filtered = _allOptions;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final normalized = query.trim().toLowerCase();
    setState(() {
      _filtered = normalized.isEmpty
          ? _allOptions
          : _allOptions
              .where(
                (option) => option.label.toLowerCase().contains(normalized),
              )
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: 'Search timezones…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(child: Text('No matching timezones'))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final option = _filtered[index];
                          return ListTile(
                            title: Text(option.label),
                            trailing: option.value == widget.initialValue
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () =>
                                Navigator.of(context).pop(option.value),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
