"""Verify the actual release ZIP has no extra metadata, comments, or AppleDouble files."""
import struct
import sys
import zipfile
from pathlib import PurePosixPath

if len(sys.argv) != 2:
    sys.exit("Usage: python3 scripts/check-release-archive.py RELEASE_ZIP")

try:
    with zipfile.ZipFile(sys.argv[1]) as archive, open(sys.argv[1], "rb") as raw:
        entries = archive.infolist()
        if not entries or archive.comment or len({entry.filename for entry in entries}) != len(entries):
            raise ValueError("Empty, commented, or duplicate-entry archive")
        for entry in entries:
            path = PurePosixPath(entry.filename)
            if (path.is_absolute() or ".." in path.parts or "\\" in entry.filename
                    or path.parts[0] != "Taskport.app"
                    or any(part.startswith("._") or part == "__MACOSX" for part in path.parts)):
                raise ValueError("Unexpected archive entry")
            if entry.extra or entry.comment:
                raise ValueError("Archive contains extra metadata or a file comment")
            if entry.date_time != (2000, 1, 1, 0, 0, 0):
                raise ValueError("Archive contains local modification timestamps")
            # The central directory and local headers have independent metadata fields.
            raw.seek(entry.header_offset)
            header = struct.unpack("<4s5H3L2H", raw.read(30))
            if header[0] != b"PK\x03\x04" or header[-1] != 0:
                raise ValueError("Local file header contains extra metadata")
        if archive.testzip() is not None:
            raise ValueError("Archive checksum mismatch")
    print(f"Checked {len(entries)} ZIP entries; neutral timestamps and no owner IDs, extra attributes, comments, or AppleDouble files.")
except (OSError, ValueError, IndexError, struct.error, zipfile.BadZipFile):
    sys.exit("Release ZIP verification failed: invalid archive or unexpected metadata.")
