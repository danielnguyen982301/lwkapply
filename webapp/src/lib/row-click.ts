import { useRouter } from 'vue-router'

// Shared "click anywhere in a directory row to open its application"
// handler - used by ApplicationListView.vue and InterviewDirectoryView.vue.
// Skips clicks that originated on an interactive element already inside
// the row (a company link, an email/LinkedIn link, an edit/delete
// button) - those either already navigate themselves, or need to do
// something other than navigate (e.g. open a confirm dialog without also
// navigating out from under it). Anywhere else in the row falls through
// to the same application-detail route those links already go to.
//
// `getApplicationId` is how each caller's row shape maps to an
// application id - ApplicationListView's row *is* the application
// (`app => app.id`), while InterviewDirectoryView's rows only embed one
// (`row => row.application.id`). ContactDirectoryView.vue used to be a
// third caller here too, before Contact became a top-level resource with
// no single parent application left to click through to - see
// types/contact.ts.
export function useApplicationRowClick<T>(getApplicationId: (row: T) => string) {
  const router = useRouter()

  return function handleRowClick(event: { originalEvent: Event; data: T }) {
    const target = event.originalEvent.target as HTMLElement
    if (target.closest('a, button')) return
    router.push({ name: 'application-detail', params: { id: getApplicationId(event.data) } })
  }
}
