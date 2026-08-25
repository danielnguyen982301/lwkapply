import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/application_contacts_api.dart' show ContactsException;
import '../data/contact_directory_api.dart';
import '../domain/contact.dart';
import 'contact_directory_state.dart';

/// Mirrors InterviewsListController's fetch/append split for infinite
/// scroll, but as a plain (non-`.family`) StateNotifier, same as
/// ApplicationsListController/DocumentDirectoryController — this screen
/// shows one global, cross-application list, not something scoped per
/// application.
///
/// **No longer read-only.** This is now the primary place to manage the
/// contact directory (add/edit/delete), not a read-only
/// cross-application view — `Contact` is a top-level, user-owned
/// resource now (see contact.dart's doc comment), so there's no other
/// screen with a better claim to owning these actions.
/// `prepend`/`replaceById`/`removeById` patch local state the same way
/// `DocumentDirectoryController` does for its own library list.
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

  /// After a successful create — always the newest contact, so always
  /// belongs at index 0 regardless of how many pages are already loaded.
  /// Mirrors DocumentDirectoryController.prepend.
  void prepend(Contact contact) {
    state = state.copyWith(
      items: [contact, ...state.items],
      total: state.total + 1,
    );
  }

  /// After a successful edit — same item, same position.
  void replaceById(Contact updated) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.id == updated.id) updated else item,
      ],
    );
  }

  /// After a successful delete — no reorder ambiguity, same reasoning
  /// as every other list's `removeById`.
  void removeById(String id) {
    if (!state.items.any((item) => item.id == id)) return;
    state = state.copyWith(
      items: state.items.where((item) => item.id != id).toList(),
      total: state.total > 0 ? state.total - 1 : 0,
    );
  }
}

final contactDirectoryControllerProvider = StateNotifierProvider.autoDispose<
    ContactDirectoryController, ContactDirectoryState>((ref) {
  return ContactDirectoryController(ref.watch(contactDirectoryApiProvider));
});
