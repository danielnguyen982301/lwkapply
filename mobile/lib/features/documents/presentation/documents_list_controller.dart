import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/documents_api.dart';
import '../domain/document.dart';
import 'documents_list_state.dart';

/// Mirrors InterviewsListController's `.family`-scoped infinite-scroll
/// shape (features/interviews/presentation/
/// interviews_list_controller.dart), scoped to one application.
///
/// Deliberately scoped to list/pagination only — same boundary
/// InterviewsListController/ApplicationsListController draw. Mutations
/// go through `DocumentsApi` directly from DocumentsPanel, then call
/// back into this controller to patch local state.
///
/// One real difference from Interviews: this list is ordered by
/// `created_at DESC` (see documents.py::list_documents), and only
/// `file_type` is ever editable in place — nothing about an upload or
/// an edit can change a document's position in that ordering the way
/// editing an interview's `scheduled_at` can. So unlike
/// InterviewsListController (full `refresh()` after every
/// create/update, since position genuinely is ambiguous there), this
/// controller patches `items` directly for all three mutations:
/// `prepend()` after upload (a new document is always the newest, so
/// always belongs at the front — correct even with several
/// infinite-scrolled pages already loaded), `replaceById()` after a
/// file-type edit (position never changes), and `removeById()` after
/// delete (same no-reorder reasoning every other list already uses).
class DocumentsListController extends StateNotifier<DocumentsListState> {
  DocumentsListController(this._api, this._applicationId)
      : super(const DocumentsListState()) {
    fetchFirstPage();
  }

  final DocumentsApi _api;
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

  /// After a successful upload — always the newest document, so always
  /// belongs at index 0 regardless of how many pages are already
  /// loaded (see class doc comment).
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

final documentsListControllerProvider = StateNotifierProvider.autoDispose
    .family<DocumentsListController, DocumentsListState, String>(
        (ref, applicationId) {
  return DocumentsListController(
    ref.watch(documentsApiProvider),
    applicationId,
  );
});
