"""
Validates client-reported IANA timezone names before persisting them to
User.timezone. Shared by every call site that accepts one (register,
login, refresh - see api/v1/endpoints/auth.py) so there's exactly one
place that decides what counts as a valid tz name, rather than a
zoneinfo check duplicated per schema/endpoint.
"""

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def is_valid_timezone(value: str) -> bool:
    try:
        ZoneInfo(value)
        return True
    except (ZoneInfoNotFoundError, ValueError):
        return False
