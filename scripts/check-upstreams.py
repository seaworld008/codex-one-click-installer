#!/usr/bin/env python3
"""Scheduled upstream probes for official Codex distribution endpoints."""

from __future__ import annotations

import base64
import binascii
import json
import re
import ssl
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass


USER_AGENT = "codex-one-click-installer-upstream-smoke/2.0"
BOOTSTRAPS = {
    "POSIX bootstrap": (
        "https://chatgpt.com/codex/install.sh",
        b"#!/bin/sh",
        b"https://releases.openai.com/codex",
    ),
    "PowerShell bootstrap": (
        "https://chatgpt.com/codex/install.ps1",
        b"[CmdletBinding()]",
        b"https://releases.openai.com/codex",
    ),
}
LATEST_METADATA = "https://releases.openai.com/codex/channels/latest"
NPM_LATEST = "https://registry.npmjs.org/@openai%2Fcodex/latest"
WINDOWS_DOCS = "https://learn.chatgpt.com/docs/windows/windows-app"
WINDOWS_INSTALLER = "https://get.microsoft.com/installer/download/9PLM9XGG6VKS"
WINDOWS_MSIX = {
    "Windows x64 MSIX": "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix",
    "Windows arm64 MSIX": "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix",
}
LINUX_DOCS = "https://learn.chatgpt.com/docs/linux/linux-app"
LINUX_PACKAGES = {
    "Linux deb x64": "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb",
    "Linux deb arm64": "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb",
    "Linux rpm x64": "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm",
    "Linux rpm arm64": "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.aarch64.rpm",
}
STORE_ID = "9PLM9XGG6VKS"
REQUIRED_RELEASE_ASSETS = {
    "codex-aarch64-apple-darwin.tar.gz",
    "codex-aarch64-pc-windows-msvc.exe.zip",
    "codex-aarch64-unknown-linux-musl.tar.gz",
    "codex-x86_64-apple-darwin.tar.gz",
    "codex-x86_64-pc-windows-msvc.exe.zip",
    "codex-x86_64-unknown-linux-musl.tar.gz",
}


class ProbeError(RuntimeError):
    pass


@dataclass(frozen=True)
class Response:
    url: str
    status: int
    headers: object
    body: bytes


def fetch(
    url: str,
    *,
    limit: int,
    headers: dict[str, str] | None = None,
    allow_truncated: bool = False,
) -> Response:
    request_headers = {
        "Accept": "*/*",
        "User-Agent": USER_AGENT,
    }
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(url, headers=request_headers, method="GET")
    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(request, timeout=45, context=context) as response:
            body = response.read(limit + 1)
            if len(body) > limit:
                if not allow_truncated:
                    raise ProbeError(f"{url} exceeded the {limit}-byte probe limit")
                body = body[:limit]
            return Response(
                url=response.geturl(),
                status=response.status,
                headers=response.headers,
                body=body,
            )
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise ProbeError(f"{url} request failed: {exc}") from exc


def parse_json(response: Response, label: str) -> dict[str, object]:
    try:
        value = json.loads(response.body.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ProbeError(f"{label} did not return valid UTF-8 JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ProbeError(f"{label} JSON root is not an object")
    return value


def parse_bounded_total_bytes(
    response: Response,
    label: str,
    *,
    minimum: int,
    maximum: int,
) -> int:
    """Resolve the full download size from a range or full response."""
    if response.status == 206:
        content_range = response.headers.get("Content-Range", "")
        match = re.fullmatch(
            r"bytes\s+\d+-\d+/(\d+)", content_range.strip(), re.IGNORECASE
        )
        if match is None:
            raise ProbeError(
                f"{label} returned an invalid Content-Range: {content_range!r}"
            )
        total_bytes = int(match.group(1))
    elif response.status == 200:
        content_length = response.headers.get("Content-Length", "").strip()
        if not re.fullmatch(r"\d+", content_length):
            raise ProbeError(f"{label} returned no valid total Content-Length")
        total_bytes = int(content_length)
    else:
        raise ProbeError(f"{label} returned HTTP {response.status}")

    if not minimum <= total_bytes <= maximum:
        raise ProbeError(f"{label} reported an unsafe total size: {total_bytes} bytes")
    return total_bytes


def validate_sha512_integrity(value: object) -> None:
    if not isinstance(value, str) or not value.startswith("sha512-"):
        raise ProbeError("npm latest metadata has no SHA-512 integrity value")
    encoded = value.removeprefix("sha512-")
    try:
        digest = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ProbeError("npm latest metadata has malformed SHA-512 integrity") from exc
    if len(digest) != 64:
        raise ProbeError("npm latest metadata SHA-512 integrity is not 64 bytes")


def validate_linux_package_prefix(filename: str, body: bytes) -> None:
    if filename.endswith(".deb"):
        expected = b"!<arch>\n"
        package_type = "Debian"
    elif filename.endswith(".rpm"):
        expected = b"\xed\xab\xee\xdb"
        package_type = "RPM"
    else:
        raise ProbeError(f"unsupported Linux package filename: {filename}")
    if not body.startswith(expected):
        raise ProbeError(f"{filename} did not return a {package_type} package prefix")


def check_bootstraps() -> None:
    for label, (url, prefix, marker) in BOOTSTRAPS.items():
        response = fetch(url, limit=1024 * 1024)
        if response.status != 200:
            raise ProbeError(f"{label} returned HTTP {response.status}")
        if not response.url.startswith("https://releases.openai.com/codex/install."):
            raise ProbeError(f"{label} redirected to unexpected URL: {response.url}")
        if not response.body.lstrip(b"\xef\xbb\xbf").startswith(prefix):
            raise ProbeError(f"{label} did not have the expected script header")
        if marker not in response.body:
            raise ProbeError(f"{label} did not reference the official release service")
        print(f"OK: {label} ({len(response.body)} bytes, {response.url})")


def check_release_metadata() -> None:
    response = fetch(LATEST_METADATA, limit=4 * 1024 * 1024)
    metadata = parse_json(response, "latest release metadata")
    tag = metadata.get("tag_name")
    if not isinstance(tag, str) or not re.fullmatch(
        r"rust-v\d+\.\d+\.\d+(?:-(?:alpha|beta)(?:\.\d+){0,2})?", tag
    ):
        raise ProbeError(f"latest release metadata has an invalid tag_name: {tag!r}")
    raw_assets = metadata.get("assets")
    if not isinstance(raw_assets, list):
        raise ProbeError("latest release metadata contains no assets array")

    assets: dict[str, dict[str, object]] = {}
    for item in raw_assets:
        if isinstance(item, dict) and isinstance(item.get("name"), str):
            assets[item["name"]] = item
    missing = sorted(REQUIRED_RELEASE_ASSETS - assets.keys())
    if missing:
        raise ProbeError(f"latest release metadata is missing assets: {', '.join(missing)}")

    for name in sorted(REQUIRED_RELEASE_ASSETS):
        asset = assets[name]
        digest = asset.get("digest")
        url = asset.get("browser_download_url")
        if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ProbeError(f"{name} has an invalid SHA-256 digest")
        if not isinstance(url, str) or not url.startswith(
            "https://releases.openai.com/codex/releases/"
        ):
            raise ProbeError(f"{name} has a non-official download URL: {url!r}")
    print(f"OK: latest release metadata ({tag}, {len(raw_assets)} assets)")


def check_npm_latest() -> None:
    response = fetch(NPM_LATEST, limit=1024 * 1024)
    metadata = parse_json(response, "npm latest metadata")
    if metadata.get("name") != "@openai/codex":
        raise ProbeError("npm latest metadata returned the wrong package")
    version = metadata.get("version")
    if not isinstance(version, str) or not re.fullmatch(
        r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version
    ):
        raise ProbeError(f"npm latest metadata has an invalid version: {version!r}")
    dist = metadata.get("dist")
    tarball = dist.get("tarball") if isinstance(dist, dict) else None
    integrity = dist.get("integrity") if isinstance(dist, dict) else None
    if not isinstance(tarball, str) or not tarball.startswith(
        "https://registry.npmjs.org/@openai/codex/-/"
    ):
        raise ProbeError(f"npm latest metadata has an unexpected tarball: {tarball!r}")
    validate_sha512_integrity(integrity)
    print(f"OK: npm latest metadata (@openai/codex {version})")


def check_windows_app() -> None:
    docs = fetch(WINDOWS_DOCS, limit=3 * 1024 * 1024)
    if docs.status != 200:
        raise ProbeError(f"Windows documentation returned HTTP {docs.status}")
    if STORE_ID.encode("ascii") not in docs.body:
        raise ProbeError(f"Windows documentation no longer references Store ID {STORE_ID}")

    installer = fetch(
        WINDOWS_INSTALLER,
        limit=16,
        headers={"Range": "bytes=0-1", "Accept": "application/octet-stream"},
        allow_truncated=True,
    )
    if installer.status not in {200, 206}:
        raise ProbeError(f"Windows web installer returned HTTP {installer.status}")
    if not installer.body.startswith(b"MZ"):
        raise ProbeError("Windows web installer did not return a PE file prefix")
    disposition = installer.headers.get("Content-Disposition", "")
    if "installer" not in disposition.lower():
        raise ProbeError("Windows web installer response has no installer filename")

    for label, url in WINDOWS_MSIX.items():
        package = fetch(
            url,
            limit=16,
            headers={"Range": "bytes=0-3", "Accept": "application/octet-stream"},
            allow_truncated=True,
        )
        if package.status not in {200, 206}:
            raise ProbeError(f"{label} returned HTTP {package.status}")
        if not package.body.startswith(b"PK"):
            raise ProbeError(f"{label} did not return a ZIP/MSIX prefix")
        total_bytes = parse_bounded_total_bytes(
            package,
            label,
            minimum=1024 * 1024,
            maximum=1024 * 1024 * 1024,
        )
        print(f"OK: {label} range probe ({total_bytes} total bytes)")
    print(f"OK: Windows docs and Store web installer ({STORE_ID})")


def check_linux_app() -> None:
    docs = fetch(LINUX_DOCS, limit=3 * 1024 * 1024)
    if docs.status != 200:
        raise ProbeError(f"Linux documentation returned HTTP {docs.status}")
    for url in LINUX_PACKAGES.values():
        filename = url.rsplit("/", 1)[-1]
        if filename.encode("ascii") not in docs.body:
            raise ProbeError(f"Linux documentation no longer references {filename}")

    for label, url in LINUX_PACKAGES.items():
        filename = url.rsplit("/", 1)[-1]
        package = fetch(
            url,
            limit=16,
            headers={"Range": "bytes=0-7", "Accept": "application/octet-stream"},
            allow_truncated=True,
        )
        if package.status not in {200, 206}:
            raise ProbeError(f"{label} returned HTTP {package.status}")
        validate_linux_package_prefix(filename, package.body)
        total_bytes = parse_bounded_total_bytes(
            package,
            label,
            minimum=10 * 1024 * 1024,
            maximum=800 * 1024 * 1024,
        )
        print(f"OK: {label} range probe ({total_bytes} total bytes)")


def main() -> int:
    checks = [
        ("official bootstrap endpoints", check_bootstraps),
        ("releases.openai.com latest metadata", check_release_metadata),
        ("npm latest metadata", check_npm_latest),
        ("Windows app URLs", check_windows_app),
        ("Linux app URLs", check_linux_app),
    ]
    failures: list[str] = []
    for label, check in checks:
        try:
            check()
        except ProbeError as exc:
            failures.append(f"{label}: {exc}")
            print(f"ERROR: {label}: {exc}", file=sys.stderr)

    if failures:
        print(
            f"Upstream smoke failed: {len(failures)} of {len(checks)} checks failed.",
            file=sys.stderr,
        )
        return 1
    print(f"Upstream smoke passed: {len(checks)} check groups.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
