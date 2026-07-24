from fastapi import APIRouter

from app.api.v1.endpoints import (
    applications,
    auth,
    contacts,
    documents,
    interviews,
    users,
)

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(
    applications.router, prefix="/applications", tags=["applications"]
)

# Interviews/Documents/Contacts are nested under a specific application -
# they never exist independently of one, so their CRUD routes and ownership
# checks are scoped through applications/{application_id}/... rather than
# living at the top level. See docstrings in each endpoint module.
api_router.include_router(
    interviews.router,
    prefix="/applications/{application_id}/interviews",
    tags=["interviews"],
)

# Interviews additionally has one flat, top-level, read-only route: a
# cross-application directory of every interview the user owns (mirrors
# the Contacts directory route below). Creation/update/delete stay
# nested above - this is just a different read path over the same rows.
api_router.include_router(
    interviews.directory_router, prefix="/interviews", tags=["interviews"]
)
api_router.include_router(
    documents.router,
    prefix="/applications/{application_id}/documents",
    tags=["documents"],
)
api_router.include_router(
    contacts.router,
    prefix="/applications/{application_id}/contacts",
    tags=["contacts"],
)

# Contacts additionally has one flat, top-level, read-only route: a
# cross-application directory of every contact the user owns (used by the
# "Contacts" nav item). Creation/update/delete stay nested above - this is
# just a different read path over the same rows.
api_router.include_router(
    contacts.directory_router, prefix="/contacts", tags=["contacts"]
)
