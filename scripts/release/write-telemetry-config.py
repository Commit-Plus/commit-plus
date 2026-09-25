#!/usr/bin/env python3
"""Write bundle configuration from the release environment, never a fallback ID."""

import os
from pathlib import Path
import plistlib
import uuid


def main():
    raw_app_id = os.environ.get("TELEMETRYDECK_APP_ID", "").strip()
    try:
        app_id = uuid.UUID(raw_app_id)
    except ValueError:
        raise SystemExit("TELEMETRYDECK_APP_ID must be a non-empty UUID") from None
    if app_id.int == 0:
        raise SystemExit("TELEMETRYDECK_APP_ID must not be the nil UUID")

    path = Path(__file__).resolve().parents[2] / "macgit" / "TelemetryDeck-Info.plist"
    path.write_bytes(plistlib.dumps({"AppID": str(app_id).upper()}))


if __name__ == "__main__":
    main()
