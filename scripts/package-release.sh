#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SCRIPT_DIR/release-files.txt"
OUTPUT_DIR="$REPO_ROOT/dist"
SOURCE_REF=""
PACKAGE_NAME="codex-one-click-installer"

usage() {
  cat <<'EOF'
Usage: scripts/package-release.sh [--source-ref REF] [--output-dir DIR]

Without --source-ref, package the current working tree. Release automation passes
the exact tag so every staged source file is read from that immutable Git object.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source-ref)
      [ "$#" -ge 2 ] && [ -n "$2" ] || {
        echo "ERROR: --source-ref requires a non-empty value" >&2
        exit 2
      }
      SOURCE_REF="$2"
      shift
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || { echo "ERROR: --output-dir requires a value" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for command_name in git install mktemp python3 tar unzip; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $command_name" >&2
    exit 1
  }
done
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "ERROR: sha256sum or shasum is required" >&2
  exit 1
fi

mapfile_compat() {
  local line previous=""
  RELEASE_FILES=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
    esac
    case "$line" in
      /*|*\\*|*:*|*$'\r'*|*$'\t'*|.|..|./*|../*|*/.|*/..|*/./*|*/../*|*//*)
        echo "ERROR: unsafe release manifest path: $line" >&2
        exit 1
        ;;
    esac
    if [ -n "$previous" ] && ! LC_ALL=C test "$previous" \< "$line"; then
      echo "ERROR: release manifest must be strictly sorted without duplicates: $line" >&2
      exit 1
    fi
    RELEASE_FILES+=("$line")
    previous="$line"
  done < "$MANIFEST"
}

assert_regular_source() {
  local root="$1"
  local relative="$2"
  local current="$root"
  local component
  local components=()

  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="$current/$component"
    if [ -L "$current" ]; then
      echo "ERROR: release source must not contain symbolic links: $relative" >&2
      exit 1
    fi
  done
  if [ ! -f "$current" ]; then
    echo "ERROR: release source is missing or not a regular file: $relative" >&2
    exit 1
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mapfile_compat
[ "${#RELEASE_FILES[@]}" -gt 0 ] || {
  echo "ERROR: release manifest is empty: $MANIFEST" >&2
  exit 1
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-release.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
SOURCE_DIR="$TEMP_DIR/source"
mkdir -p "$SOURCE_DIR"

if [ -n "$SOURCE_REF" ]; then
  SOURCE_COMMIT="$(
    git -C "$REPO_ROOT" rev-parse --verify "${SOURCE_REF}^{commit}"
  )"
  git -C "$REPO_ROOT" archive --format=tar "$SOURCE_COMMIT" -- "${RELEASE_FILES[@]}" |
    tar -xf - -C "$SOURCE_DIR"
  VERSION="$(git -C "$REPO_ROOT" show "${SOURCE_COMMIT}:VERSION" | tr -d '\r\n')"
  export SOURCE_DATE_EPOCH
  SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" show -s --format=%ct "$SOURCE_COMMIT")"
else
  VERSION="$(tr -d '\r\n' < "$REPO_ROOT/VERSION")"
  for relative in "${RELEASE_FILES[@]}"; do
    source_path="$REPO_ROOT/$relative"
    assert_regular_source "$REPO_ROOT" "$relative"
    mkdir -p "$SOURCE_DIR/$(dirname -- "$relative")"
    install -m 0644 "$source_path" "$SOURCE_DIR/$relative"
  done
  if git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$REPO_ROOT" show -s --format=%ct HEAD)}"
  else
    export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
  fi
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: VERSION must be a stable SemVer (x.y.z), got: $VERSION" >&2
  exit 1
fi

PACKAGE_BASENAME="${PACKAGE_NAME}-v${VERSION}"
STAGE_ROOT="$TEMP_DIR/$PACKAGE_BASENAME"
mkdir -p "$STAGE_ROOT"

for relative in "${RELEASE_FILES[@]}"; do
  source_path="$SOURCE_DIR/$relative"
  assert_regular_source "$SOURCE_DIR" "$relative"
  case "$relative" in
    *.sh|*.command) mode=0755 ;;
    *) mode=0644 ;;
  esac
  mkdir -p "$STAGE_ROOT/$(dirname -- "$relative")"
  install -m "$mode" "$source_path" "$STAGE_ROOT/$relative"
done

python3 - "$STAGE_ROOT" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
for path in root.rglob("*"):
    if not path.is_file():
        continue
    data = path.read_bytes()
    if path.suffix.lower() == ".ps1":
        if data.startswith(b"\xef\xbb\xbf"):
            data = data[3:]
        data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        data = data.replace(b"\n", b"\r\n")
        data = b"\xef\xbb\xbf" + data
    elif path.suffix.lower() == ".cmd":
        if data.startswith(b"\xef\xbb\xbf"):
            data = data[3:]
        data.decode("ascii")
        data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        data = data.replace(b"\n", b"\r\n")
    else:
        data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    path.write_bytes(data)
PY

SBOM_ASSET="$TEMP_DIR/${PACKAGE_BASENAME}.spdx.json"
python3 "$SCRIPT_DIR/generate-sbom.py" \
  --root "$STAGE_ROOT" \
  --version "$VERSION" \
  --name "$PACKAGE_NAME" \
  --output "$SBOM_ASSET"
install -m 0644 "$SBOM_ASSET" "$STAGE_ROOT/SBOM.spdx.json"
python3 "$SCRIPT_DIR/verify-release.py" --root "$STAGE_ROOT" --manifest "$MANIFEST"

mkdir -p "$OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f \
  \( -name "${PACKAGE_NAME}-v*.zip" -o -name "${PACKAGE_NAME}-v*.tar.gz" \
     -o -name "${PACKAGE_NAME}-v*.spdx.json" -o -name SHA256SUMS \) -delete

ZIP_PATH="$OUTPUT_DIR/${PACKAGE_BASENAME}.zip"
TAR_PATH="$OUTPUT_DIR/${PACKAGE_BASENAME}.tar.gz"
SBOM_PATH="$OUTPUT_DIR/${PACKAGE_BASENAME}.spdx.json"

python3 "$SCRIPT_DIR/build-archives.py" \
  --root "$STAGE_ROOT" \
  --zip "$ZIP_PATH" \
  --tar-gz "$TAR_PATH" \
  --epoch "$SOURCE_DATE_EPOCH"
install -m 0644 "$SBOM_ASSET" "$SBOM_PATH"

ZIP_EXTRACT="$TEMP_DIR/verify-zip"
TAR_EXTRACT="$TEMP_DIR/verify-tar"
mkdir -p "$ZIP_EXTRACT" "$TAR_EXTRACT"
unzip -q "$ZIP_PATH" -d "$ZIP_EXTRACT"
tar -xzf "$TAR_PATH" -C "$TAR_EXTRACT"
python3 "$SCRIPT_DIR/verify-release.py" \
  --root "$ZIP_EXTRACT/$PACKAGE_BASENAME" \
  --manifest "$MANIFEST"
python3 "$SCRIPT_DIR/verify-release.py" \
  --root "$TAR_EXTRACT/$PACKAGE_BASENAME" \
  --manifest "$MANIFEST"

CHECKSUMS_TMP="$TEMP_DIR/SHA256SUMS"
for asset in "$ZIP_PATH" "$TAR_PATH" "$SBOM_PATH"; do
  printf '%s  %s\n' "$(sha256_file "$asset")" "$(basename -- "$asset")"
done > "$CHECKSUMS_TMP"
install -m 0644 "$CHECKSUMS_TMP" "$OUTPUT_DIR/SHA256SUMS"

(
  cd "$OUTPUT_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check SHA256SUMS
  else
    shasum -a 256 --check SHA256SUMS
  fi
)

printf 'Release package ready: %s\n' "$OUTPUT_DIR"
