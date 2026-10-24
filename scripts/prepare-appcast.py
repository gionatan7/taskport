#!/usr/bin/env python3
"""Create and sign the GitHub Releases appcast locally; never publish or export private keys."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import html
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/gionatan7/taskport"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--notes", type=Path, help="optional plain-text release notes")
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        parser.error("the appcast output already exists; choose a fresh path")
    with zipfile.ZipFile(args.archive) as archive:
        info = plistlib.loads(archive.read("Taskport.app/Contents/Info.plist"))
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if not isinstance(version, str) or not isinstance(build, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[1-9]\d*", build):
        parser.error("expected a release version and a positive integer build number")
    if args.archive.name != f"Taskport-{version}-macos-arm64.zip":
        parser.error("archive name does not match its embedded release version")
    if info.get("SUFeedURL") != REPOSITORY + "/releases/latest/download/appcast.xml":
        parser.error("the app is configured for a different update feed")
    canonical = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    if info.get("SUPublicEDKey") != canonical.get("SUPublicEDKey"):
        parser.error("archive public key does not match Taskport's update key")
    signer = ROOT / ".build/artifacts/sparkle/Sparkle/bin/sign_update"
    public_key = subprocess.run([str(signer.with_name("generate_keys")), "--account", "app.taskport.desktop", "-p"],
                                check=True, capture_output=True, text=True).stdout.strip()
    if public_key != info["SUPublicEDKey"]:
        raise RuntimeError("Keychain signing key does not match the app's public verification key")
    signature = subprocess.run([str(signer), "--account", "app.taskport.desktop", "-p", str(args.archive)],
                               check=True, capture_output=True, text=True).stdout.strip()
    if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", signature):
        raise RuntimeError("invalid signature output")
    # Verify archive signing before advertising it; no private key is written to disk.
    subprocess.run([str(signer), "--account", "app.taskport.desktop", "--verify", str(args.archive), signature],
                   check=True, capture_output=True)
    ET.register_namespace("sparkle", SPARKLE)
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Taskport updates"
    ET.SubElement(channel, "link").text = REPOSITORY + "/releases"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "Taskport " + version
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    ET.SubElement(item, "link").text = REPOSITORY + "/releases/tag/v" + version
    ET.SubElement(item, "{" + SPARKLE + "}version").text = build
    ET.SubElement(item, "{" + SPARKLE + "}shortVersionString").text = version
    ET.SubElement(item, "{" + SPARKLE + "}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
    ET.SubElement(item, "{" + SPARKLE + "}hardwareRequirements").text = "arm64"
    if args.notes:
        ET.SubElement(item, "description").text = "<p>" + html.escape(args.notes.read_text()).replace("\n", "<br>") + "</p>"
    ET.SubElement(item, "enclosure", {
        "url": REPOSITORY + "/releases/download/v" + version + "/" + args.archive.name,
        "length": str(args.archive.stat().st_size), "type": "application/octet-stream",
        "{" + SPARKLE + "}edSignature": signature,
        "{" + SPARKLE + "}os": "macos",
    })
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with args.output.open("xb") as file:
            ET.ElementTree(rss).write(file, encoding="utf-8", xml_declaration=True)
        subprocess.run([str(signer), "--account", "app.taskport.desktop", str(args.output)], check=True, capture_output=True)
        subprocess.run([str(signer), "--account", "app.taskport.desktop", "--verify", str(args.output)], check=True, capture_output=True)
    except Exception:
        args.output.unlink(missing_ok=True)
        raise
    print("Signed appcast prepared. Attach appcast.xml, the audited ZIP/checksum, and matching source/relink materials to the same GitHub Release.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile, subprocess.CalledProcessError):
        raise SystemExit("Appcast preparation failed; nothing was published. Check archive metadata, the pinned Sparkle tools, and Keychain access.")
