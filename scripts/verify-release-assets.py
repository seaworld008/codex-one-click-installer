#!/usr/bin/env python3
"""Strictly verify and compare the four public release assets."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


SAFE_BASENAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
CHECKSUM_LINE = re.compile(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)")


class VerificationError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expected_names(basename: str) -> tuple[tuple[str, ...], tuple[str, ...]]:
    if not SAFE_BASENAME.fullmatch(basename) or basename in {".", ".."}:
        raise VerificationError(f"unsafe release basename: {basename!r}")
    payloads = (
        f"{basename}.zip",
        f"{basename}.tar.gz",
        f"{basename}.spdx.json",
    )
    return payloads, (*payloads, "SHA256SUMS")


def verify_directory(root: Path, basename: str) -> dict[str, str]:
    if root.is_symlink():
        raise VerificationError(f"release asset directory must not be a symlink: {root}")
    root = root.resolve()
    payloads, expected = expected_names(basename)
    expected_set = set(expected)
    if not root.is_dir():
        raise VerificationError(f"release asset directory is missing: {root}")

    entries = list(root.iterdir())
    actual: set[str] = set()
    for entry in entries:
        if entry.is_symlink():
            raise VerificationError(f"release asset must not be a symlink: {entry.name}")
        if not entry.is_file():
            raise VerificationError(
                f"release asset directory contains a non-file entry: {entry.name}"
            )
        actual.add(entry.name)
    if actual != expected_set or len(entries) != len(expected):
        missing = sorted(expected_set - actual)
        unexpected = sorted(actual - expected_set)
        raise VerificationError(
            "release asset file list mismatch"
            f"; missing={missing or 'none'}; unexpected={unexpected or 'none'}"
        )

    checksum_path = root / "SHA256SUMS"
    if checksum_path.stat().st_size > 4096:
        raise VerificationError("SHA256SUMS exceeds the 4096-byte safety limit")
    checksum_bytes = checksum_path.read_bytes()
    if not checksum_bytes.endswith(b"\n") or b"\r" in checksum_bytes:
        raise VerificationError("SHA256SUMS must use canonical LF with a final newline")
    try:
        checksum_text = checksum_bytes.decode("ascii")
    except UnicodeDecodeError as exc:
        raise VerificationError("SHA256SUMS must be ASCII") from exc

    records: dict[str, str] = {}
    for line in checksum_text.splitlines():
        match = CHECKSUM_LINE.fullmatch(line)
        if match is None:
            raise VerificationError(f"invalid SHA256SUMS record: {line!r}")
        digest, filename = match.groups()
        if filename in records:
            raise VerificationError(f"duplicate SHA256SUMS record: {filename}")
        records[filename] = digest
    if set(records) != set(payloads) or len(records) != len(payloads):
        raise VerificationError("SHA256SUMS must bind exactly the three payload assets")

    for filename in payloads:
        actual_digest = sha256(root / filename)
        if actual_digest != records[filename]:
            raise VerificationError(
                f"SHA-256 mismatch for {filename}: "
                f"expected {records[filename]}, got {actual_digest}"
            )
    return records


def compare_directories(local: Path, downloaded: Path, basename: str) -> None:
    _, expected = expected_names(basename)
    verify_directory(local, basename)
    verify_directory(downloaded, basename)
    for filename in expected:
        local_path = local.resolve() / filename
        downloaded_path = downloaded.resolve() / filename
        if local_path.stat().st_size != downloaded_path.stat().st_size:
            raise VerificationError(f"downloaded asset size differs: {filename}")
        if sha256(local_path) != sha256(downloaded_path):
            raise VerificationError(f"downloaded asset bytes differ: {filename}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-dir", type=Path, required=True)
    parser.add_argument("--basename", required=True)
    parser.add_argument("--compare-dir", type=Path)
    args = parser.parse_args()

    try:
        if args.compare_dir is None:
            verify_directory(args.local_dir, args.basename)
        else:
            compare_directories(args.local_dir, args.compare_dir, args.basename)
    except (OSError, VerificationError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.compare_dir is None:
        print(f"Release assets verified: {args.local_dir.resolve()}")
    else:
        print(
            "Release assets verified byte-for-byte: "
            f"{args.local_dir.resolve()} == {args.compare_dir.resolve()}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
