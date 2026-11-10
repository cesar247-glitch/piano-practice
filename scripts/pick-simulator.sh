#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator, preferring iPhone 14, then the newest iPhone.
set -euo pipefail
xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
phones = []
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    ver = tuple(int(x) for x in re.findall(r"\d+", runtime.split("iOS")[-1]))
    for d in devices:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            phones.append((ver, d["name"], d["udid"]))
if not phones:
    sys.exit("no available iPhone simulator")
phones.sort(reverse=True)
for ver, name, udid in phones:
    if name == "iPhone 14":
        print(udid); sys.exit(0)
plain = [p for p in phones if re.fullmatch(r"iPhone \d+", p[1])]
print((plain or phones)[0][2])
'
