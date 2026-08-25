import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/application_contacts_api.dart';
import '../domain/contact.dart';
import 'contacts_list_state.dart';

/// Mirrors DocumentsListController's `.family`-scoped infinite-scroll
/// shape, scoped to one application — this application's *attached*
/// contacts (via `ApplicationContactsApi`, the `ApplicationContact`
/// join), not contacts it owns outright (there's no more "owns" — see
/// contact.dart's doc comment).
///
/// Replaces `ContactsPanel`'s old plain local `State`: the nested list
/// used to be small and unpaginated, so a Riverpod controller wasn't
/// worth it (see the previous version of contacts_panel.dart's doc
/// comment) — now that the backend paginates this endpoint too (a
/// contact can be reused across applications, same reason `Document`
/// needed this), it needs the same infinite-scroll bookkeeping every
/// other paginated panel already has.
///
/// Deliberately scoped to list/pagination only — same boundary
/// DocumentsListController draws. Mutations (attach, create-then-attach,
/// edit, detach) go through `ApplicationContactsApi`/`ContactDirectoryApi`
/// directly from `ContactsPanel`, then call back into this controller to
/// patch local state.
///
/// Same no-reorder-ambiguity reasoning `DocumentsListController` always
/// had (`GET /applications/{id}/contacts` orders by attach time
/// descending, and neither attaching nor editing a contact's fields can
/// change that position): `prepend()` after attach/create-then-attach
/// (always newest, always belongs at index 0), `replaceById()` after an
/// edit (position unchanged), `removeById()` after detach.
class ContactsListController extends StateNotifier<ContactsListState> {
  ContactsListController(this._api, this._applicationId)
      : super(const ContactsListState()) {
    fetchFirstPage();
  }

  final ApplicationContactsApi _api;
  final String _applicationId;

  Future<void> fetchFirstPage() async {
    state = state.copyWith(status: RequestStatus.loading, clearError: true);
    try {
      final response = await _api.list(
        _applicationId,
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
        _applicationId,
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
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> refresh() => fetchFirstPage();

  /// After a successful attach (or create-then-attach) — always the
  /// newest attachment, so always belongs at index 0 regardless of how
  /// many pages are already loaded (see class doc comment).
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

  /// After a successful detach — no reorder ambiguity, same reasoning
  /// as every other list's `removeById`. The contact itself still exists
  /// in the directory; only this application's link is gone.
  void removeById(String id) {
    if (!state.items.any((item) => item.id == id)) return;
    state = state.copyWith(
      items: state.items.where((item) => item.id != id).toList(),
      total: state.total > 0 ? state.total - 1 : 0,
    );
  }
}

final contactsListControllerProvider = StateNotifierProvider.autoDispose
    .family<ContactsListController, ContactsListState, String>((
  ref,
  applicationId,
) {
  return ContactsListController(
    ref.watch(applicationContactsApiProvider),
    applicationId,
  );
});
