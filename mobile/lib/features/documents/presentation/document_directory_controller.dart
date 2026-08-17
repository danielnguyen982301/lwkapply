import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/application_documents_api.dart' show DocumentsException;
import '../data/document_directory_api.dart';
import '../domain/document.dart';
import 'document_directory_state.dart';

/// Combines ContactDirectoryController's `setSearch` and
/// InterviewDirectoryController's `setResultFilter` shapes — the same
/// fetch/append infinite-scroll split as both, plus two independent
/// filter setters instead of one, since `GET /documents` supports
/// `search` and `file_type` together (see DocumentDirectoryApi's doc
/// comment). Plain (non-`.family`) StateNotifier, same reasoning as the
/// other two directory controllers: one global, cross-application list.
///
/// **No longer read-only.** This is now the primary place to manage the
/// document library (upload/edit/download/delete), not a read-only
/// cross-application view — `Document` is a top-level, user-owned
/// resource now (see document.dart's doc comment), so there's no other
/// screen with a better claim to owning these actions.
/// `prepend`/`replaceById`/`removeById` patch local state the same way
/// `DocumentsListController` does for its own (now application-scoped
/// attach/detach) list.
class DocumentDirectoryController
    extends StateNotifier<DocumentDirectoryState> {
  DocumentDirectoryController(this._api)
      : super(const DocumentDirectoryState()) {
    fetchFirstPage();
  }

  final DocumentDirectoryApi _api;

  Future<void> fetchFirstPage() async {
    state = state.copyWith(status: RequestStatus.loading, clearError: true);
    try {
      final response = await _api.list(
        search: state.search,
        fileType: state.fileTypeFilter,
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
        search: state.search,
        fileType: state.fileTypeFilter,
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
      // Keep whatever's already loaded — surface the error without
      // wiping a list that was fetched successfully a moment ago.
      state = state.copyWith(
        status: RequestStatus.error,
        errorMessage: e.message,
      );
    }
  }

  Future<void> refresh() => fetchFirstPage();

  /// Applies a new search term (independent of the file-type filter) and
  /// jumps back to page 1, mirroring ContactDirectoryController.setSearch.
  Future<void> setSearch(String search) async {
    if (search == state.search) return;
    state = state.copyWith(search: search);
    await fetchFirstPage();
  }

  /// Applies a new file-type filter (or clears it, if `fileType` is
  /// `null`), independent of `search`, and jumps back to page 1 —
  /// mirrors InterviewDirectoryController.setResultFilter.
  Future<void> setFileTypeFilter(DocumentType? fileType) async {
    if (fileType == state.fileTypeFilter) return;
    state = state.copyWith(
      fileTypeFilter: fileType,
      clearFileTypeFilter: fileType == null,
    );
    await fetchFirstPage();
  }

  /// Clears both filters at once and jumps back to page 1 — mirrors
  /// webapp's `clearFilters()` in DocumentDirectoryView.vue, which the
  /// two single-filter setters above don't cover on their own (each only
  /// resets its own filter).
  Future<void> clearFilters() async {
    if (state.search.isEmpty && state.fileTypeFilter == null) return;
    state = state.copyWith(search: '', clearFileTypeFilter: true);
    await fetchFirstPage();
  }

  /// After a successful upload — always the newest document, so always
  /// belongs at index 0 regardless of how many pages are already
  /// loaded. Mirrors DocumentsListController.prepend.
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

final documentDirectoryControllerProvider = StateNotifierProvider.autoDispose<
    DocumentDirectoryController, DocumentDirectoryState>((ref) {
  return DocumentDirectoryController(ref.watch(documentDirectoryApiProvider));
});
