from pydantic import BaseModel, ConfigDict, Field


class UserSettingsRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    reminder_lead_hours: int | None = None
    notifications_enabled: bool
    email_notifications_enabled: bool
    push_notifications_enabled: bool
    in_app_notifications_enabled: bool


class UserSettingsUpdate(BaseModel):
    """Body for PATCH /users/me/settings. Every field optional and applied
    via exclude_unset (see the endpoint) - an *omitted* field is left
    untouched, while an explicit `null` for reminder_lead_hours resets it
    to the global settings.REMINDER_LEAD_HOURS default. That distinction
    only works because this is exclude_unset, not exclude_none."""

    reminder_lead_hours: int | None = Field(default=None, ge=1, le=168)
    notifications_enabled: bool | None = None
    email_notifications_enabled: bool | None = None
    push_notifications_enabled: bool | None = None
    in_app_notifications_enabled: bool | None = None
