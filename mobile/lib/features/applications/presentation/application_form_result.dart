import '../domain/application.dart';

/// What `ApplicationFormScreen` hands back via `context.pop(...)` when it
/// closes with a change made (as opposed to the user just backing out,
/// which pops `null`).
///
/// Kept as an explicit result type — rather than always popping the
/// `Application` and inferring "was this a delete?" from some sentinel —
/// so the list screen can react correctly to each case without
/// ambiguity: a save should refresh (the list is server-sorted by
/// `updated_at desc`, so an edited item's position may have changed and
/// a local patch could leave it in the wrong place — see
/// ApplicationsListController's docs), while a delete only ever needs to
/// remove one known id, which is safe to do locally without a refetch.
sealed class ApplicationFormResult {
  const ApplicationFormResult();
}

class ApplicationSaved extends ApplicationFormResult {
  const ApplicationSaved(this.application);
  final Application application;
}

class ApplicationDeleted extends ApplicationFormResult {
  const ApplicationDeleted(this.id);
  final String id;
}
