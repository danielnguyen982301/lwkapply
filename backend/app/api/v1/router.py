from fastapi import APIRouter

from app.api.v1.endpoints import (
    ai,
    analytics,
    application_contacts,
    application_documents,
    applications,
    auth,
    contacts,
    documents,
    interviews,
    notifications,
    users,
)

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(
    applications.router, prefix="/applications", tags=["applications"]
)

# Analytics is read-only and flat like the three directory routers below,
# but unlike them it was never a nested-only resource to begin with -
# there's no per-application analytics view, so there's no nested router
# half to pair it with. Every query inside aggregates over the current
# user's own applications/interviews (see analytics.py's own docstring).
api_router.include_router(analytics.router, prefix="/analytics", tags=["analytics"])

# Interviews are nested under a specific application - an interview never
# exists independently of one, so its CRUD routes and ownership checks are
# scoped through applications/{application_id}/... rather than living at
# the top level. See docstrings in each endpoint module.
api_router.include_router(
    interviews.router,
    prefix="/applications/{application_id}/interviews",
    tags=["interviews"],
)

# Interviews additionally has one flat, top-level, read-only route: a
# cross-application directory of every interview the user owns. Creation/
# update/delete stay nested above - this is just a different read path
# over the same rows.
api_router.include_router(
    interviews.directory_router, prefix="/interviews", tags=["interviews"]
)

# Documents and Contacts are the opposite of Interviews: top-level,
# user-owned resources in their own right (create/read/update/delete all
# live here, unscoped by any application), reusable across zero or more
# applications - see app/models/document.py / app/models/contact.py.
# application_documents/application_contacts below only handle attaching/
# detaching an existing document or contact to/from a specific
# application.
api_router.include_router(documents.router, prefix="/documents", tags=["documents"])
api_router.include_router(
    application_documents.router,
    prefix="/applications/{application_id}/documents",
    tags=["documents"],
)
api_router.include_router(contacts.router, prefix="/contacts", tags=["contacts"])
api_router.include_router(
    application_contacts.router,
    prefix="/applications/{application_id}/contacts",
    tags=["contacts"],
)

# AI features (Resume Parser + ATS Score - TODO.md "AI Features") - two
# top-level, user-owned resources (like Application), not nested under
# /applications/{id}/. Both POST routes are async: they return 202 with
# a pending row and dispatch a Celery task; see app/tasks/ai_celery.py.
api_router.include_router(ai.router, prefix="/ai", tags=["ai"])

# In-app notification feed (the "bell icon") - top-level, user-owned,
# read-mostly, same shape as documents/ai above. The only producer is
# app/tasks/reminders_celery.py; this router only reads/marks rows read.
api_router.include_router(
    notifications.router, prefix="/notifications", tags=["notifications"]
)
