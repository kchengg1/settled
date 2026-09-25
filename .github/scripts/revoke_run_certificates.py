#!/usr/bin/env python3
"""Revoke the Apple Development certificates this release run created.

Cloud signing makes xcodebuild create a fresh "Created via API" development
certificate on every runner, and the runner's private key is thrown away
with the machine. Left alone they pile up until Apple refuses to issue more
and archiving fails. Only certificates found in this runner's keychain are
touched, so certificates made anywhere else are never revoked.

Uses only the standard library and the openssl CLI, both on the macOS runner.
Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
"""

import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
NAME = "Created via API"


def run_certificate_serials():
    """Serial numbers of the API-created certificates in this runner's keychain."""
    found = subprocess.run(["security", "find-certificate", "-a", "-c", NAME, "-p"],
                           capture_output=True, text=True).stdout
    pems = re.findall(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", found, re.S)
    serials = set()
    for pem in pems:
        out = subprocess.run(["openssl", "x509", "-noout", "-serial"],
                             input=pem, capture_output=True, text=True, check=True).stdout
        serials.add(normalize(out.strip().split("=", 1)[1]))
    return serials


def normalize(serial):
    return serial.upper().lstrip("0")


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """ECDSA signature from DER (what openssl emits) to the raw r||s JWS wants."""
    def read_int(offset):
        assert der[offset] == 0x02
        length = der[offset + 1]
        value = der[offset + 2:offset + 2 + length].lstrip(b"\0").rjust(32, b"\0")
        return value, offset + 2 + length

    assert der[0] == 0x30
    offset = 3 if der[1] & 0x80 else 2
    r, offset = read_int(offset)
    s, _ = read_int(offset)
    return r + s


def token(key_id, issuer_id, key_path):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claims = b64url(json.dumps({"iss": issuer_id, "iat": now, "exp": now + 600,
                                "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{claims}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                         input=signing_input, capture_output=True, check=True).stdout
    return f"{header}.{claims}.{b64url(der_to_raw(der))}"


def request(method, path, jwt):
    req = urllib.request.Request(API + path, method=method,
                                 headers={"Authorization": f"Bearer {jwt}"})
    with urllib.request.urlopen(req, timeout=30) as response:
        body = response.read()
    return json.loads(body) if body else None


def main():
    serials = run_certificate_serials()
    if not serials:
        print("No certificates were created on this runner; nothing to revoke.")
        return 0

    jwt = token(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"],
                os.environ["ASC_KEY_PATH"])
    listing = request("GET", "/certificates?limit=200"
                      "&filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT"
                      "&fields[certificates]=serialNumber,name", jwt)
    matches = [c for c in listing["data"]
               if normalize(c["attributes"]["serialNumber"]) in serials]
    for certificate in matches:
        request("DELETE", f"/certificates/{certificate['id']}", jwt)
        print(f"Revoked {certificate['attributes']['name']} "
              f"(serial {certificate['attributes']['serialNumber']})")
    missing = len(serials) - len(matches)
    if missing:
        print(f"::warning::{missing} certificate(s) from this run were not found "
              "in App Store Connect and were left alone.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # Cleanup must never fail a finished release.
        print(f"::warning::Could not revoke this run's development certificate: {error}. "
              "Revoke 'Created via API' certificates in the developer portal "
              "if archiving later reports the certificate limit.")
        sys.exit(0)
