import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/contact_directory_api.dart';
import '../data/contacts_api.dart' show ContactsException;
import 'contact_directory_state.dart';

/// Mirrors InterviewsListController's fetch/append split for infinite
/// scroll (features/interviews/presentation/
/// interviews_list_controller.dart), but as a plain (non-`.family`)
/// StateNotifier, same as ApplicationsListController — this screen shows
/// one global, cross-application list, not something scoped per
/// application.
///
/// Read-only: unlike ApplicationsListController/InterviewsListController,
/// there's no create/update/delete here to react to — `GET /contacts` is
/// the only call this feature makes (see ContactDirectoryApi's doc
/// comment for why edits happen from the owning application instead, not
/// this screen).
class ContactDirectoryController extends StateNotifier<ContactDirectoryState> {
  ContactDirectoryController(this._api) : super(const ContactDirectoryState()) {
    fetchFirstPage();
  }

  final ContactDirectoryApi _api;

  Future<void> fetchFirstPage() async {
    state = state.copyWith(status: RequestStatus.loading, clearError: true);
    try {
      final response = await _api.list(
        search: state.search,
        page: 1,
        pageSize: state.pageSize,
      );
      state = state.copyWith(
        items: response.items,
        total: response.total,
        page: response.page,
        pageSize: response.pageSize,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on ContactsException catch (e) {
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> loadNextPage() async {
    if (state.status == RequestStatus.loadingMore || !state.hasMore) return;
    state = state.copyWith(status: RequestStatus.loadingMore);
    try {
      final nextPage = state.page + 1;
      final response = await _api.list(
        search: state.search,
        page: nextPage,
        pageSize: state.pageSize,
      );
      state = state.copyWith(
        items: [...state.items, ...response.items],
        total: response.total,
        page: response.page,
        status: RequestStatus.idle,
        clearError: true,
      );
    } on ContactsException catch (e) {
      // Keep whatever's already loaded — surface the error without
      // wiping a list that was fetched successfully a moment ago.
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> refresh() => fetchFirstPage();

  /// Applies a new search term and jumps back to page 1, mirroring
  /// ApplicationsListController.setFilters' search handling.
  Future<void> setSearch(String search) async {
    if (search == state.search) return;
    state = state.copyWith(search: search);
    await fetchFirstPage();
  }
}

final contactDirectoryControllerProvider = StateNotifierProvider.autoDispose<
    ContactDirectoryController, ContactDirectoryState>((ref) {
  return ContactDirectoryController(ref.watch(contactDirectoryApiProvider));
});
