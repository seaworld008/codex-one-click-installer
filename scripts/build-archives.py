#!/usr/bin/env python3
"""Build deterministic ZIP and tar.gz archives with portable Unix modes."""

from __future__ import annotations

import argparse
import gzip
import os
import stat
import tarfile
import zipfile
from pathlib import Path


ZIP_MIN_EPOCH = 315532800  # 1980-01-01T00:00:00Z


def archive_paths(root: Path) -> list[Path]:
    return [root, *sorted(root.rglob("*"), key=lambda path: path.as_posix())]


def normalize_metadata(root: Path, epoch: int) -> None:
    for path in reversed(archive_paths(root)):
        if path.is_symlink():
            raise ValueError(f"release tree must not contain symlinks: {path}")
        os.utime(path, (epoch, epoch), follow_symlinks=False)


def zip_datetime(epoch: int) -> tuple[int, int, int, int, int, int]:
    import datetime as dt

    instant = dt.datetime.fromtimestamp(max(epoch, ZIP_MIN_EPOCH), tz=dt.timezone.utc)
    # ZIP stores seconds at two-second resolution.
    return (
        instant.year,
        instant.month,
        instant.day,
        instant.hour,
        instant.minute,
        instant.second - (instant.second % 2),
    )


def build_zip(root: Path, output: Path, epoch: int) -> None:
    base = root.parent
    timestamp = zip_datetime(epoch)
    with zipfile.ZipFile(
        output,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        strict_timestamps=True,
    ) as archive:
        archive.comment = b""
        for path in archive_paths(root):
            relative = path.relative_to(base).as_posix()
            is_directory = path.is_dir()
            name = f"{relative}/" if is_directory else relative
            mode = 0o755 if is_directory else stat.S_IMODE(path.stat().st_mode)
            file_type = stat.S_IFDIR if is_directory else stat.S_IFREG
            info = zipfile.ZipInfo(name, date_time=timestamp)
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = ((file_type | mode) & 0xFFFF) << 16
            if is_directory:
                info.external_attr |= 0x10
                archive.writestr(info, b"")
            else:
                archive.writestr(info, path.read_bytes())


def tar_info(name: str, mode: int, epoch: int, *, is_directory: bool) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name=f"{name}/" if is_directory else name)
    info.type = tarfile.DIRTYPE if is_directory else tarfile.REGTYPE
    info.mode = mode
    info.mtime = epoch
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    return info


def build_tar_gz(root: Path, output: Path, epoch: int) -> None:
    base = root.parent
    with output.open("wb") as raw:
        with gzip.GzipFile(
            filename="",
            mode="wb",
            fileobj=raw,
            compresslevel=9,
            mtime=epoch,
        ) as compressed:
            with tarfile.open(
                fileobj=compressed,
                mode="w",
                format=tarfile.PAX_FORMAT,
            ) as archive:
                for path in archive_paths(root):
                    relative = path.relative_to(base).as_posix()
                    if path.is_dir():
                        archive.addfile(
                            tar_info(relative, 0o755, epoch, is_directory=True)
                        )
                    else:
                        info = tar_info(
                            relative,
                            stat.S_IMODE(path.stat().st_mode),
                            epoch,
                            is_directory=False,
                        )
                        info.size = path.stat().st_size
                        with path.open("rb") as handle:
                            archive.addfile(info, fileobj=handle)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--zip", dest="zip_path", type=Path, required=True)
    parser.add_argument("--tar-gz", dest="tar_path", type=Path, required=True)
    parser.add_argument("--epoch", type=int, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    zip_path = args.zip_path.resolve()
    tar_path = args.tar_path.resolve()
    if not root.is_dir():
        raise ValueError(f"release root is not a directory: {root}")
    if args.epoch < 0:
        raise ValueError("SOURCE_DATE_EPOCH must not be negative")

    normalize_metadata(root, args.epoch)
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    tar_path.parent.mkdir(parents=True, exist_ok=True)
    build_zip(root, zip_path, args.epoch)
    build_tar_gz(root, tar_path, args.epoch)
    os.chmod(zip_path, 0o644)
    os.chmod(tar_path, 0o644)
    os.utime(zip_path, (args.epoch, args.epoch))
    os.utime(tar_path, (args.epoch, args.epoch))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
