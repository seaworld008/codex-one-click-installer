#!/usr/bin/env python3
"""Generate a small deterministic SPDX 2.3 JSON document using stdlib only."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path


def digest(path: Path, algorithm: str) -> str:
    hasher = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def created_at() -> str:
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
    instant = dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc)
    return instant.strftime("%Y-%m-%dT%H:%M:%SZ")


def build_document(root: Path, version: str, package_name: str) -> dict[str, object]:
    paths = sorted(path for path in root.rglob("*") if path.is_file())
    if not paths:
        raise ValueError(f"SBOM root contains no files: {root}")

    files: list[dict[str, object]] = []
    sha1_values: list[str] = []
    namespace_seed = hashlib.sha256()
    relationships: list[dict[str, str]] = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": "SPDXRef-Package",
        }
    ]

    for index, path in enumerate(paths, start=1):
        relative = path.relative_to(root).as_posix()
        sha1 = digest(path, "sha1")
        sha256 = digest(path, "sha256")
        sha1_values.append(sha1)
        namespace_seed.update(relative.encode("utf-8"))
        namespace_seed.update(b"\0")
        namespace_seed.update(sha256.encode("ascii"))
        spdx_id = f"SPDXRef-File-{index}"
        files.append(
            {
                "fileName": f"./{relative}",
                "SPDXID": spdx_id,
                "checksums": [
                    {"algorithm": "SHA1", "checksumValue": sha1},
                    {"algorithm": "SHA256", "checksumValue": sha256},
                ],
                "licenseConcluded": "NOASSERTION",
                "copyrightText": "NOASSERTION",
            }
        )
        relationships.append(
            {
                "spdxElementId": "SPDXRef-Package",
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": spdx_id,
            }
        )

    verification = hashlib.sha1("".join(sorted(sha1_values)).encode("ascii")).hexdigest()
    namespace_hash = namespace_seed.hexdigest()
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"{package_name}-{version}",
        "documentNamespace": (
            "https://github.com/seaworld008/codex-one-click-installer/"
            f"spdx/{version}/{namespace_hash}"
        ),
        "creationInfo": {
            "created": created_at(),
            "creators": ["Tool: codex-one-click-installer/scripts/generate-sbom.py"],
        },
        "packages": [
            {
                "name": package_name,
                "SPDXID": "SPDXRef-Package",
                "versionInfo": version,
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": True,
                "licenseConcluded": "MIT",
                "licenseDeclared": "MIT",
                "copyrightText": "NOASSERTION",
                "packageVerificationCode": {
                    "packageVerificationCodeValue": verification,
                },
            }
        ],
        "files": files,
        "relationships": relationships,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--name", default="codex-one-click-installer")
    args = parser.parse_args()

    root = args.root.resolve()
    output = args.output.resolve()
    document = build_document(root, args.version, args.name)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
