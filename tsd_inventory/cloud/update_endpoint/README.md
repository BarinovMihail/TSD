# TSD update endpoint

Cloud Function returns the update manifest from a private Yandex Object Storage
bucket and replaces `apkKey` with a presigned APK URL valid for 10 minutes.

## Deployed resources

- Bucket: `tsd-inventory-updates-b1g3poudt`
- Service account: `tsd-update-endpoint` (`ajepolrs35p8pj8j4p2h`)
- Cloud Function: `tsd-update-endpoint` (`d4eotl7blcec645fmdot`)
- API Gateway: `tsd-update-api` (`d5dee87rdn4hcm079v90`)
- Endpoint: `https://d5dee87rdn4hcm079v90.tmjd4m4j.apigw.yandexcloud.net/updates/latest`

The endpoint requires the `X-Update-Token` header. Its value is stored in the
`tsd-update-endpoint-token` Lockbox secret. It must be used only by the 1C
backend and must never be embedded into the Android application.

## Bucket layout

```text
manifest.json
releases/
  tsd-inventory-0.2.6-8.apk
```

Example `manifest.json`:

```json
{
  "versionName": "0.2.6",
  "versionCode": 8,
  "apkKey": "releases/tsd-inventory-0.2.6-8.apk",
  "sha256": "<lowercase APK SHA-256>",
  "releaseNotes": "Описание изменений"
}
```

Upload the APK first and `manifest.json` last. This prevents clients from
seeing a manifest that points to an APK which has not finished uploading.

Without the header, a healthy deployed endpoint responds with HTTP 401. Until
`manifest.json` is uploaded, an authorized request responds with HTTP 502.

## Local verification

```powershell
cd cloud/update_endpoint
python -m unittest -v
Compress-Archive -Path index.py,requirements.txt -DestinationPath function.zip -Force
```
