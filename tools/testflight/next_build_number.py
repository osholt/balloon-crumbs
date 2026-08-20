#!/usr/bin/env python3
"""Ask App Store Connect for the next unused build number.

Apple reserves a build number permanently once it accepts an upload, and refuses
a repeat with an error that does not obviously say so. Deriving the number from
`pubspec.yaml` guesses at that state and drifts the moment anybody uploads
without committing, which is exactly what happened here: the pubspec said 22
while Apple had already taken 23.

Tail End Charlie sidesteps this by using the GitHub run number, which is
monotonic because CI increments it. There is no CI upload path here, so instead
this asks the only authority that actually knows.

Prints one integer: the highest build number Apple holds for the bundle ID, plus
one. Prints nothing and exits non-zero if it cannot find out, so a caller can
fall back rather than upload a number that will be rejected.

    tools/testflight/next_build_number.py dev.osholt.ballooncrumbs

Reads APPSTORE_CONNECT_API_KEY_ID and APPSTORE_CONNECT_API_ISSUER_ID from the
environment, and the private key from
~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8. The key is used to sign a
short-lived token and is never printed, copied or sent anywhere but Apple.
"""

from __future__ import annotations

import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

API_ROOT = "https://api.appstoreconnect.apple.com/v1"


def _b64(payload: bytes) -> str:
    return base64.urlsafe_b64encode(payload).rstrip(b"=").decode()


def token(key_id: str, issuer_id: str, key_path: pathlib.Path) -> str:
    """An ES256 JWT for the App Store Connect API.

    Signed with `cryptography` rather than PyJWT, which is not installed and is
    not worth adding to the server's environment for a build script. The one
    subtlety: JWS wants the ECDSA signature as raw r||s, and `cryptography`
    returns DER, so it has to be unpacked and re-emitted as two fixed-width
    integers. A DER signature here fails as "invalid token" with nothing to say
    the encoding is the problem.
    """
    private_key = serialization.load_pem_private_key(
        key_path.read_bytes(), password=None
    )
    if not isinstance(private_key, ec.EllipticCurvePrivateKey):
        raise SystemExit("the App Store Connect key is not an EC private key")

    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {
        "iss": issuer_id,
        "iat": now,
        # Apple rejects anything over 20 minutes.
        "exp": now + 600,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(claims).encode())}"
    )
    der = private_key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input}.{_b64(signature)}"


def get(path: str, bearer: str) -> dict:
    request = urllib.request.Request(
        f"{API_ROOT}{path}", headers={"Authorization": f"Bearer {bearer}"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    bundle_id = argv[1]

    key_id = os.environ.get("APPSTORE_CONNECT_API_KEY_ID", "")
    issuer_id = os.environ.get("APPSTORE_CONNECT_API_ISSUER_ID", "")
    if not key_id or not issuer_id:
        print(
            "next_build_number: set APPSTORE_CONNECT_API_KEY_ID and "
            "APPSTORE_CONNECT_API_ISSUER_ID",
            file=sys.stderr,
        )
        return 1

    key_path = (
        pathlib.Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    )
    if not key_path.is_file():
        print(f"next_build_number: no private key at {key_path}", file=sys.stderr)
        return 1

    try:
        bearer = token(key_id, issuer_id, key_path)
        apps = get(f"/apps?filter[bundleId]={bundle_id}&limit=1", bearer)
        if not apps.get("data"):
            print(
                f"next_build_number: no app record for {bundle_id}. Create it in "
                "App Store Connect first.",
                file=sys.stderr,
            )
            return 1
        app_id = apps["data"][0]["id"]
        # 200 is the maximum page size, and more than enough history to find the
        # highest number. Sorting by -version is a string sort on Apple's side,
        # which puts "9" above "10", so the maximum is taken here instead.
        builds = get(
            f"/builds?filter[app]={app_id}&limit=200&fields[builds]=version",
            bearer,
        )
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:400]
        print(f"next_build_number: {error.code} from Apple: {detail}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"next_build_number: {error}", file=sys.stderr)
        return 1

    numbers = []
    for build in builds.get("data", []):
        version = build.get("attributes", {}).get("version")
        if version and version.isdigit():
            numbers.append(int(version))
    print(max(numbers, default=0) + 1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
