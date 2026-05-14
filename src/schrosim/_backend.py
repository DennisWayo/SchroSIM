from __future__ import annotations

import os
import shutil
import stat
from pathlib import Path

_BACKEND_BINARY_NAME = "schrosim-cli"
_BACKEND_ENV_VAR = "SCHROSIM_CLI"


def find_backend_binary() -> Path | None:
    overridden = _resolve_override()
    if overridden is not None:
        return overridden

    installed = shutil.which(_BACKEND_BINARY_NAME)
    if installed:
        return Path(installed)

    packaged = _resolve_packaged_backend()
    if packaged is not None:
        _ensure_executable(packaged)
        return packaged

    return None


def _resolve_override() -> Path | None:
    raw = os.environ.get(_BACKEND_ENV_VAR)
    if not raw:
        return None

    candidate = Path(raw).expanduser()
    if _is_executable_file(candidate):
        return candidate
    return None


def _resolve_packaged_backend() -> Path | None:
    package_root = Path(__file__).resolve().parent
    candidate = package_root / "_bin" / _BACKEND_BINARY_NAME
    if candidate.is_file():
        return candidate
    return None


def _is_executable_file(path: Path) -> bool:
    return path.is_file() and os.access(path, os.X_OK)


def _ensure_executable(path: Path) -> None:
    mode = path.stat().st_mode
    if mode & stat.S_IXUSR:
        return
    path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
