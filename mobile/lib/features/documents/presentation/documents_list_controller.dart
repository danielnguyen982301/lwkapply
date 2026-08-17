import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/application_documents_api.dart';
import '../domain/document.dart';
import 'documents_list_state.dart';

/// Mirrors InterviewsListController's `.family`-scoped infinite-scroll
/// shape (features/interviews/presentation/
/// interviews_list_controller.dart), scoped to one application — this
/// application's *attached* documents (via `ApplicationDocumentsApi`,
/// the `ApplicationDocument` join), not documents it owns outright
/// (there's no more "owns" — see document.dart's doc comment).
///
/// Deliberately scoped to list/pagination only — same boundary
/// InterviewsListController/ApplicationsListController draw. Mutations
/// (attach, upload-then-attach, edit type, detach) go through
/// `ApplicationDocumentsApi`/`DocumentDirectoryApi` directly from
/// `DocumentsPanel`, then call back into this controller to patch local
/// state.
///
/// Same no-reorder-ambiguity reasoning `DocumentsListController` always
/// had (`GET /applications/{id}/documents` orders by attach time
/// descending, and neither attaching nor editing `file_type` can change
/// that position): `prepend()` after attach/upload-then-attach (always
/// newest, always belongs at index 0), `replaceById()` after a
/// file-type edit (position unchanged), `removeById()` after detach.
class DocumentsListController extends StateNotifier<DocumentsListState> {
  DocumentsListController(this._api, this._applicationId)
      : super(const DocumentsListState()) {
    fetchFirstPage();
  }

  final ApplicationDocumentsApi _api;
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
    } on DocumentsException catch (e) {
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
    } on DocumentsException catch (e) {
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> refresh() => fetchFirstPage();

  /// After a successful attach (or upload-then-attach) — always the
  /// newest attachment, so always belongs at index 0 regardless of how
  /// many pages are already loaded (see class doc comment).
  void prepend(Document document) {
    state = state.copyWith(
      items: [document, ...state.items],
      total: state.total + 1,
    );
  }

  /// After a successful file-type edit — same item, same position.
  void replaceById(Document updated) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.id == updated.id) updated else item,
      ],
    );
  }

  /// After a successful detach — no reorder ambiguity, same reasoning
  /// as every other list's `removeById`. The document itself still
  /// exists in the library; only this application's link is gone.
  void removeById(String id) {
    if (!state.items.any((item) => item.id == id)) return;
    state = state.copyWith(
      items: state.items.where((item) => item.id != id).toList(),
      total: state.total > 0 ? state.total - 1 : 0,
    );
  }
}

final documentsListControllerProvider = StateNotifierProvider.autoDispose
    .family<DocumentsListController, DocumentsListState, String>(
        (ref, applicationId) {
  return DocumentsListController(
    ref.watch(applicationDocumentsApiProvider),
    applicationId,
  );
});
