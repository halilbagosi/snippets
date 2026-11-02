#!/usr/bin/env python3
"""Adds one release to the Sparkle appcast (site/appcast.xml), newest first.

Called by release.sh --final; see the README's Releasing section. Refuses a
build number that isn't higher than every one already listed, because
Sparkle compares CFBundleVersion and would never offer it.
"""
import argparse
import email.utils
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SP = "{%s}" % SPARKLE


def require_newer(channel, build, path):
    listed = [int(v.text) for v in channel.iter(SP + "version")]
    if listed and build <= max(listed):
        print(f"error: build {build} is not newer than {max(listed)}, already in {path}",
              file=sys.stderr)
        sys.exit(1)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--appcast", required=True)
    p.add_argument("--build", required=True, type=int)
    # release.sh runs this before the archive, so a stale build fails in seconds.
    p.add_argument("--check", action="store_true",
                   help="only verify --build is newer; write nothing")
    for name in ("version", "url", "signature", "min-system", "notes-file", "length"):
        p.add_argument("--" + name, type=int if name == "length" else str)
    a = p.parse_args()
    if not a.check:
        missing = [n for n in ("version", "url", "signature", "min_system", "notes_file", "length")
                   if getattr(a, n) is None]
        if missing:
            p.error("required without --check: " + ", ".join("--" + n.replace("_", "-") for n in missing))

    ET.register_namespace("sparkle", SPARKLE)
    tree = ET.parse(a.appcast)
    channel = tree.getroot().find("channel")

    require_newer(channel, a.build, a.appcast)
    if a.check:
        return

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Snippets {a.version}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, SP + "version").text = str(a.build)
    ET.SubElement(item, SP + "shortVersionString").text = a.version
    ET.SubElement(item, SP + "minimumSystemVersion").text = a.min_system
    with open(a.notes_file, encoding="utf-8") as f:
        ET.SubElement(item, "description").text = f.read()
    ET.SubElement(item, "enclosure", {
        "url": a.url,
        "length": str(a.length),
        "type": "application/octet-stream",
        SP + "edSignature": a.signature,
    })

    first_item = next((i for i, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(first_item, item)
    ET.indent(tree, space="  ")
    tree.write(a.appcast, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
