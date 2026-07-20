import json
import os
import unittest
from unittest.mock import patch

import index


class UpdateEndpointTest(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(
            os.environ,
            {
                "S3_ACCESS_KEY_ID": "A" * 25,
                "S3_SECRET_ACCESS_KEY": "B" * 40,
                "BUCKET": "test-bucket",
                "UPDATE_TOKEN": "test-token",
            },
            clear=True,
        )
        self.env.start()

    def tearDown(self):
        self.env.stop()

    def test_rejects_missing_token(self):
        response = index.handler({"headers": {}}, None)
        self.assertEqual(response["statusCode"], 401)

    @patch("index.urllib.request.urlopen")
    def test_returns_signed_apk_url(self, urlopen):
        manifest = {
            "versionName": "0.2.6",
            "versionCode": 8,
            "apkKey": "releases/tsd-inventory-0.2.6-8.apk",
            "releaseNotes": "Test",
        }
        response_context = urlopen.return_value.__enter__.return_value
        response_context.read.return_value = json.dumps(manifest).encode("utf-8")

        response = index.handler(
            {"headers": {"X-Update-Token": "test-token"}}, None
        )
        body = json.loads(response["body"])

        self.assertEqual(response["statusCode"], 200)
        self.assertNotIn("apkKey", body)
        self.assertIn("X-Amz-Signature=", body["apkUrl"])
        self.assertEqual(body["urlExpiresInSec"], 600)


if __name__ == "__main__":
    unittest.main()

