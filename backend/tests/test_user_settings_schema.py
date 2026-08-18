"""
Unit tests for app.schemas.user_settings validation rules.
"""

import pytest
from pydantic import ValidationError

from app.schemas.user_settings import UserSettingsUpdate


class TestUserSettingsUpdateValidation:
    def test_all_fields_optional_and_default_none(self):
        payload = UserSettingsUpdate()
        assert payload.reminder_lead_hours is None
        assert payload.notifications_enabled is None
        assert payload.email_notifications_enabled is None
        assert payload.push_notifications_enabled is None

    def test_reminder_lead_hours_below_minimum_is_rejected(self):
        with pytest.raises(ValidationError):
            UserSettingsUpdate(reminder_lead_hours=0)

    def test_reminder_lead_hours_above_maximum_is_rejected(self):
        with pytest.raises(ValidationError):
            UserSettingsUpdate(reminder_lead_hours=169)

    def test_reminder_lead_hours_at_bounds_is_accepted(self):
        assert UserSettingsUpdate(reminder_lead_hours=1).reminder_lead_hours == 1
        assert UserSettingsUpdate(reminder_lead_hours=168).reminder_lead_hours == 168

    def test_explicit_null_reminder_lead_hours_is_accepted(self):
        # Explicit null (not omission) is how a client resets to the
        # global default - the ge/le bounds only apply to the int branch
        # of `int | None`, so None must pass regardless of them.
        payload = UserSettingsUpdate(reminder_lead_hours=None)
        assert "reminder_lead_hours" in payload.model_fields_set
        assert payload.reminder_lead_hours is None

    def test_omitted_reminder_lead_hours_is_distinguishable_from_explicit_null(self):
        # exclude_unset (used by the endpoint) relies on this distinction
        # to tell "the client didn't mention this field" apart from "the
        # client explicitly wants it reset to null".
        omitted = UserSettingsUpdate()
        assert "reminder_lead_hours" not in omitted.model_fields_set
