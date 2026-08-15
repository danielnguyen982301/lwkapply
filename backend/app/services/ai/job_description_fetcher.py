"""
Fetches and extracts job-posting text from an Application.job_url, for
ATS Score's "prefer job_url over asking the user to paste anything" flow
(app/tasks/ai.py::score_ats_task).

This is the first place the backend fetches a user-supplied URL from
server-side code - every other outbound call (R2, Resend, FCM) hits a
fixed, trusted endpoint. Without safeguards, a malicious job_url
(http://169.254.169.254/..., http://localhost:6379/..., an internal
Docker service name, etc.) could turn this into a probe against internal
infrastructure the API/worker container can reach. _is_safe_url() below
is the SSRF guard: http(s)-only, and the hostname must resolve
exclusively to public IPs - re-checked on every redirect hop, not just
the original URL, since a public URL can still redirect to an internal
one.

fetch_job_description() returns None (never raises) for every "couldn't
get anything usable" outcome - blocked scheme/IP, timeout, non-2xx, or
an extraction result too short to be a real job posting. Callers treat
None as "fall back to asking the user to paste it" (see
app/tasks/ai.py), not as an error to propagate directly.
"""

import ipaddress
import logging
import socket
from urllib.parse import urlparse

import httpx
import trafilatura

logger = logging.getLogger(__name__)

_TIMEOUT_SECONDS = 10.0
_MAX_RESPONSE_BYTES = 2 * 1024 * 1024  # 2MB - a job posting page, not a video
_MAX_REDIRECTS = 3
_MIN_EXTRACTED_CHARS = 100  # below this, trafilatura found ~nothing usable
_USER_AGENT = (
    "Mozilla/5.0 (compatible; LwkApplyBot/1.0; "
    "fetching a job posting URL on behalf of an authenticated user)"
)


def _is_safe_url(url: str) -> bool:
    """SSRF guard - see module docstring. Not a full defense against
    DNS-rebinding (the IP checked here isn't pinned for the actual
    connection httpx makes moments later): closing that fully would mean
    connecting to a pre-resolved IP directly with the Host header set
    separately, a meaningfully bigger change than this pass's threat
    model (an authenticated user fetching their own saved job_url, not an
    adversarial third party) calls for."""
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    hostname = parsed.hostname
    if not hostname:
        return False

    try:
        addr_infos = socket.getaddrinfo(hostname, None)
    except socket.gaierror:
        return False

    for info in addr_infos:
        ip = ipaddress.ip_address(info[4][0])
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        ):
            return False
    return True


def fetch_job_description(url: str) -> str | None:
    current_url = url

    for _ in range(_MAX_REDIRECTS + 1):
        if not _is_safe_url(current_url):
            logger.warning("Blocked unsafe/unresolvable job_url: %s", current_url)
            return None

        try:
            with httpx.stream(
                "GET",
                current_url,
                headers={"User-Agent": _USER_AGENT},
                timeout=_TIMEOUT_SECONDS,
                follow_redirects=False,
            ) as response:
                if response.is_redirect:
                    location = response.headers.get("location")
                    if not location:
                        return None
                    current_url = str(response.url.join(location))
                    continue

                if response.status_code != 200:
                    return None

                content_type = response.headers.get("content-type", "")
                if content_type and "html" not in content_type:
                    return None  # e.g. a PDF posting - not handled this pass

                # Chunked, capped read - same "don't trust the server, don't
                # buffer an unbounded body" reasoning as r2.py's
                # upload_document chunked size check.
                body = bytearray()
                for chunk in response.iter_bytes():
                    body.extend(chunk)
                    if len(body) > _MAX_RESPONSE_BYTES:
                        return None
                html = bytes(body).decode(
                    response.encoding or "utf-8", errors="replace"
                )
        except httpx.HTTPError:
            logger.warning("job_url fetch failed for %s", current_url, exc_info=True)
            return None

        extracted = trafilatura.extract(html)
        if not extracted or len(extracted) < _MIN_EXTRACTED_CHARS:
            return None
        return extracted

    logger.warning("job_url exceeded max redirects: %s", url)
    return None
