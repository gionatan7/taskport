#!/usr/bin/env python3
"""Check source-archive metadata and local identities without reporting their values."""
from pathlib import Path, PurePosixPath
import posixpath
import re
import struct
import subprocess
import sys
import tarfile
import unicodedata

ROOT = Path(__file__).resolve().parents[1]


def main():
    if len(sys.argv) != 2:
        raise RuntimeError("usage: python3 scripts/check-source-release.py SOURCE_ARCHIVE")
    archive = Path(sys.argv[1])
    identities = {str(ROOT), str(Path.home())}
    for command in (("id", "-un"), ("id", "-F"), ("git", "-C", str(ROOT), "config", "user.name"),
                    ("git", "-C", str(ROOT), "config", "user.email"),
                    ("scutil", "--get", "ComputerName"), ("scutil", "--get", "LocalHostName"),
                    ("scutil", "--get", "HostName"), ("hostname",)):
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        if result.returncode and command == ("id", "-un"):
            raise RuntimeError("cannot read local login identity")
        value = result.stdout.strip() if result.returncode == 0 else ""
        if len(value) >= 4:
            identities.add(value)
        if command == ("id", "-F"):
            identities.update(word for word in value.split() if len(word) >= 4)
    hardware = subprocess.run(("ioreg", "-rd1", "-c", "IOPlatformExpertDevice"),
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    identities.update(re.findall(r'"IOPlatform(?:SerialNumber|UUID)"\s*=\s*"([^"]+)"', hardware.stdout))
    needles = {unicodedata.normalize("NFC", value).lower().encode(encoding).lower()
               for value in identities for encoding in ("utf-8", "utf-16le", "utf-16be")}
    with archive.open("rb") as file:
        header = file.read(10)
    if len(header) != 10 or header[:3] != b"\x1f\x8b\x08" or header[3] != 0 or struct.unpack("<I", header[4:8])[0] != 946684800:
        raise RuntimeError("source gzip header contains non-neutral metadata")
    files = 0
    with tarfile.open(archive) as tar:
        top = None
        for member in tar:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts:
                raise RuntimeError("unsafe archive path")
            top = top or path.parts[0]
            if path.parts[0] != top or any(part in {".git", ".build", ".zig-cache", "zig-out", ".DS_Store"} for part in path.parts):
                raise RuntimeError("archive contains VCS metadata or a build cache")
            if member.uid or member.gid or member.uname or member.gname or member.mtime != 946684800:
                raise RuntimeError("source archive contains local ownership or timestamps")
            if set(member.pax_headers) - {"path", "linkpath"}:
                raise RuntimeError("source archive contains unexpected metadata")
            if member.issym():
                target = posixpath.normpath(posixpath.join(posixpath.dirname(member.name), member.linkname))
                if member.linkname.startswith("/") or not target.startswith(top + "/"):
                    raise RuntimeError("source link escapes archive")
            elif not (member.isfile() or member.isdir()):
                raise RuntimeError("unexpected archive entry type")
            data = (member.name + "\n" + member.linkname).encode().lower()
            if member.isfile():
                with tar.extractfile(member) as file:
                    data += file.read().lower()
                files += 1
            if any(needle in data for needle in needles):
                raise RuntimeError("source archive contains a local identity or build/home path")
    if not files:
        raise RuntimeError("source archive is empty")
    print(f"Checked {files} source/relink files: neutral metadata and no local identity/path matches.")
    print("Upstream public source and attribution remain verbatim; review them separately from local privacy.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, tarfile.TarError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
