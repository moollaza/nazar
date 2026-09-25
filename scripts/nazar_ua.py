"""The one User-Agent every script in this repo sends.

The audit, the discovery tooling and the merge/verify pass all exist to
predict one thing: whether the *app* can poll a status page. They only
predict it if they ask the way the app asks, so they all send the app's
identity, read from the same `MARKETING_VERSION` the app stamps in.

Deliberately not a browser impersonation string. Measured across 76 catalog
hosts, a full Windows desktop Chrome User-Agent produced identical results on
all 76 — impersonation buys nothing, and an honest, contactable identity lets
operators allowlist us instead of blanket-blocking.
"""

import pathlib

VERSION_CONFIG = pathlib.Path(__file__).resolve().parent.parent / "Config" / "Version.xcconfig"


def app_version(default="1.0"):
    """Read MARKETING_VERSION, the same value the app stamps into its User-Agent."""
    try:
        for line in VERSION_CONFIG.read_text().splitlines():
            if line.strip().startswith("MARKETING_VERSION"):
                return line.split("=", 1)[1].split("//")[0].strip()
    except OSError:
        pass
    return default


def user_agent():
    return f"Nazar/{app_version()} (+https://usenazar.com)"


HEADERS = {"User-Agent": user_agent()}
