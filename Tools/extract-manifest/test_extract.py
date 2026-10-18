import pathlib
import unittest

from extract import MARKER, parse_device_block


class ExtractTests(unittest.TestCase):
    def test_parses_ace68_fixture(self):
        fixture = (
            pathlib.Path(__file__).parent / "fixtures" / "ace68_snippet.txt"
        )
        source = fixture.read_text()
        index = source.find(MARKER)
        self.assertNotEqual(index, -1)

        device = parse_device_block(source, index)

        self.assertEqual(device["id"], "ace68-turbo-16k")
        self.assertEqual(device["displayName"], "Ace 68 Turbo 16K")
        self.assertEqual(device["protocolFamily"], "cz")
        self.assertEqual(device["identities"][0]["vendorId"], 14391)
        self.assertEqual(device["identities"][0]["productId"], 12326)
        self.assertEqual(device["identities"][1]["productId"], 12327)
        self.assertEqual(device["configInterface"]["usagePage"], 1)
        self.assertEqual(device["configInterface"]["usage"], 0)
        self.assertEqual(device["firmwareVersion"], 126)
        self.assertEqual(device["deviceType"], 211)
        self.assertTrue(device["verified"])


if __name__ == "__main__":
    unittest.main()
