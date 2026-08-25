#!/usr/bin/env python3
"""Validate an extracted release tree without third-party dependencies."""

from __future__ import annotations

import argparse
import json
import re
import stat
from pathlib import Path


EXECUTABLE_FILES = {
    "install-codex-linux.sh",
    "install-codex-macos.sh",
    "install-codex-unix.sh",
    "macOS双击安装Codex.command",
    "macOS双击更新Codex.command",
}
WINDOWS_TEXT_SUFFIXES = {".cmd", ".ps1"}
FORBIDDEN_SUFFIXES = {".dll", ".dmg", ".exe", ".msi", ".pkg"}
SECRET_PATTERNS = (
    re.compile(rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"),
    re.compile(rb"\bgh[oprsu]_[A-Za-z0-9]{20,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"),
)


def read_manifest(path: Path) -> list[str]:
    entries = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if len(entries) != len(set(entries)):
        raise ValueError("release manifest contains duplicate paths")
    return entries


def validate_tree(root: Path, manifest: Path) -> list[str]:
    errors: list[str] = []
    expected = set(read_manifest(manifest))
    expected.add("SBOM.spdx.json")
    actual: set[str] = set()

    for path in root.rglob("*"):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            errors.append(f"symbolic links are not allowed: {relative}")
        elif path.is_file():
            actual.add(relative)

    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing:
        errors.append(f"missing files: {', '.join(missing)}")
    if unexpected:
        errors.append(f"unexpected files: {', '.join(unexpected)}")

    for relative in sorted(actual):
        path = root / relative
        lower_parts = {part.lower() for part in path.parts}
        if {".git", ".github", "tests", "scripts"} & lower_parts:
            errors.append(f"forbidden directory in release: {relative}")
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            errors.append(f"binary installer is not allowed: {relative}")

        mode = stat.S_IMODE(path.stat().st_mode)
        is_executable = bool(mode & 0o111)
        should_execute = relative in EXECUTABLE_FILES
        if should_execute and not is_executable:
            errors.append(f"executable bit missing: {relative} ({mode:o})")
        if not should_execute and is_executable:
            errors.append(f"unexpected executable bit: {relative} ({mode:o})")

        data = path.read_bytes()
        if b"\0" in data:
            errors.append(f"NUL byte found in release text file: {relative}")
            continue
        for pattern in SECRET_PATTERNS:
            if pattern.search(data):
                errors.append(f"possible secret in {relative}")
                break

        if path.suffix.lower() in WINDOWS_TEXT_SUFFIXES:
            without_crlf = data.replace(b"\r\n", b"")
            if b"\n" in without_crlf or b"\r" in without_crlf:
                errors.append(f"Windows file does not use canonical CRLF: {relative}")
            if path.suffix.lower() == ".ps1" and not data.startswith(b"\xef\xbb\xbf"):
                errors.append(f"PowerShell file has no UTF-8 BOM: {relative}")
            if path.suffix.lower() == ".cmd":
                if data.startswith(b"\xef\xbb\xbf"):
                    errors.append(f"CMD file unexpectedly has a UTF-8 BOM: {relative}")
                try:
                    data.decode("ascii")
                except UnicodeDecodeError:
                    errors.append(f"CMD file is not pure ASCII: {relative}")
        elif b"\r" in data:
            errors.append(f"non-Windows file contains CR bytes: {relative}")

    sbom_path = root / "SBOM.spdx.json"
    if sbom_path.is_file():
        try:
            sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
            version = (root / "VERSION").read_text(encoding="utf-8").strip()
            if sbom.get("spdxVersion") != "SPDX-2.3":
                errors.append("SBOM is not SPDX-2.3")
            packages = sbom.get("packages")
            if not isinstance(packages, list) or not packages:
                errors.append("SBOM contains no package")
            elif packages[0].get("versionInfo") != version:
                errors.append("SBOM version does not match VERSION")
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            errors.append(f"invalid SBOM: {exc}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    errors = validate_tree(args.root.resolve(), args.manifest.resolve())
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"Release tree verified: {args.root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
