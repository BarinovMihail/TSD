import datetime as dt
import hashlib
import hmac
import json
import os
import urllib.parse
import urllib.request


_S3_HOST = "storage.yandexcloud.net"
_REGION = "ru-central1"
_SERVICE = "s3"


def _sign(key: bytes, message: str) -> bytes:
    return hmac.new(key, message.encode("utf-8"), hashlib.sha256).digest()


def _presigned_get_url(object_key: str, *, expires_in: int) -> str:
    access_key = os.environ["S3_ACCESS_KEY_ID"]
    secret_key = os.environ["S3_SECRET_ACCESS_KEY"]
    bucket = os.environ["BUCKET"]

    now = dt.datetime.now(dt.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    credential_scope = f"{date_stamp}/{_REGION}/{_SERVICE}/aws4_request"

    host = f"{bucket}.{_S3_HOST}"
    canonical_uri = "/" + urllib.parse.quote(object_key, safe="/-_.~")
    query = {
        "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
        "X-Amz-Credential": f"{access_key}/{credential_scope}",
        "X-Amz-Date": amz_date,
        "X-Amz-Expires": str(expires_in),
        "X-Amz-SignedHeaders": "host",
    }
    canonical_query = urllib.parse.urlencode(
        sorted(query.items()), quote_via=urllib.parse.quote, safe="~"
    )
    canonical_headers = f"host:{host}\n"
    canonical_request = "\n".join(
        [
            "GET",
            canonical_uri,
            canonical_query,
            canonical_headers,
            "host",
            "UNSIGNED-PAYLOAD",
        ]
    )
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amz_date,
            credential_scope,
            hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
        ]
    )

    date_key = _sign(("AWS4" + secret_key).encode("utf-8"), date_stamp)
    region_key = _sign(date_key, _REGION)
    service_key = _sign(region_key, _SERVICE)
    signing_key = _sign(service_key, "aws4_request")
    signature = hmac.new(
        signing_key, string_to_sign.encode("utf-8"), hashlib.sha256
    ).hexdigest()

    return (
        f"https://{host}{canonical_uri}?{canonical_query}"
        f"&X-Amz-Signature={signature}"
    )


def _header(event: dict, name: str) -> str:
    headers = event.get("headers") or {}
    wanted = name.lower()
    for key, value in headers.items():
        if key.lower() == wanted:
            return str(value)
    return ""


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def handler(event, context):
    del context

    expected_token = os.environ["UPDATE_TOKEN"]
    supplied_token = _header(event or {}, "X-Update-Token")
    if not supplied_token or not hmac.compare_digest(supplied_token, expected_token):
        return _response(401, {"error": "unauthorized"})

    manifest_key = os.environ.get("MANIFEST_KEY", "manifest.json")
    try:
        manifest_url = _presigned_get_url(manifest_key, expires_in=60)
        with urllib.request.urlopen(manifest_url, timeout=10) as response:
            manifest = json.loads(response.read().decode("utf-8"))

        apk_key = str(manifest.pop("apkKey"))
        if (
            not apk_key.startswith("releases/")
            or apk_key.startswith("/")
            or ".." in apk_key.split("/")
        ):
            raise ValueError("invalid apkKey")

        manifest["apkUrl"] = _presigned_get_url(apk_key, expires_in=600)
        manifest["urlExpiresInSec"] = 600
        return _response(200, manifest)
    except Exception:
        return _response(502, {"error": "update_manifest_unavailable"})
