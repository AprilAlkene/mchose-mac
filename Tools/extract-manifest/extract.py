#!/usr/bin/env python3
import json
import re
import sys
import urllib.request

MANIFEST_URL = "https://www.mchose.com.cn/cizhou/CZ_SHARED_DATA/asset-manifest.json?v=1"
BASE_URL = "https://www.mchose.com.cn/cizhou/CZ_SHARED_DATA/"
MARKER = 'storageKey:"Ace 68 Turbo 16K"'


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


def parse_device_block(source: str, marker_index: int) -> dict:
    identity_index = source.rfind("_identity:", 0, marker_index)
    if identity_index == -1:
        raise ValueError("missing _identity before storageKey")

    next_marker = source.find('storageKey:"', marker_index + len(MARKER))
    end = (
        next_marker
        if next_marker != -1
        else min(len(source), marker_index + 6000)
    )
    window = source[identity_index:end]

    normal = re.search(
        r"_identity:\{vendorId:(\d+),productId:(\d+)", window
    )
    boot = re.search(
        r'bootUpdateMode:"0x([0-9A-Fa-f]+)_0x([0-9A-Fa-f]+)"', window
    )
    firmware = re.search(r"(?<![A-Za-z])fwVersion:(\d+)", window)
    device_type = re.search(r"(?<![A-Za-z])type:(\d+)", window)
    storage = re.search(r'storageKey:"([^"]*)"', window)
    layout = re.search(r'layoutId:"([^"]*)"', window)

    for name, match in (
        ("_identity", normal),
        ("bootUpdateMode", boot),
        ("fwVersion", firmware),
        ("type", device_type),
        ("storageKey", storage),
    ):
        if not match:
            raise ValueError(f"missing {name}")

    return {
        "id": "ace68-turbo-16k",
        "displayName": storage.group(1),
        "protocolFamily": "cz",
        "identities": [
            {
                "vendorId": int(normal.group(1)),
                "productId": int(normal.group(2)),
                "mode": "normal",
            },
            {
                "vendorId": int(boot.group(1), 16),
                "productId": int(boot.group(2), 16),
                "mode": "boot",
            },
        ],
        "configInterface": {
            "usagePage": 1,
            "usage": 0,
            "maxReportSize": 64,
        },
        "capabilities": {
            "magnetic": True,
            "keymap": True,
            "macros": True,
            "socd": True,
            "lighting": True,
            "perKeyLighting": True,
            "gifLighting": False,
            "musicSync": False,
            "battery": False,
        },
        "profileSlots": None,
        "macroSlots": None,
        "layoutAsset": "Layouts/ace68_turbo_16k.json",
        "layoutId": layout.group(1) if layout else None,
        "lightingMatrix": None,
        "ranges": None,
        "verified": True,
        "firmwareVersion": int(firmware.group(1)),
        "deviceType": int(device_type.group(1)),
    }


def main() -> None:
    manifest = json.loads(fetch(MANIFEST_URL))
    js_files = manifest["entrypoints"]["main"]["assets"]["js"]
    source = fetch(BASE_URL + js_files[-1])

    index = source.find(MARKER)
    if index == -1:
        raise SystemExit(
            "Ace 68 Turbo 16K block not found; the bundle may have changed"
        )

    device = parse_device_block(source, index)

    output = (
        sys.argv[1]
        if len(sys.argv) > 1
        else "Resources/DeviceManifests/ace68_turbo_16k.json"
    )
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(device, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"wrote {output}")


if __name__ == "__main__":
    main()
