from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from ._backend import find_backend_binary
from ._version import __version__


def _find_repo_root(start: Path) -> Path | None:
    for candidate in [start, *start.parents]:
        if (candidate / "Package.swift").is_file():
            return candidate
    return None


def _run(command: Sequence[str]) -> int:
    completed = subprocess.run(command, check=False)
    return completed.returncode


def _is_help_or_version(args: Sequence[str]) -> bool:
    if not args:
        return True
    return args[0] in {"-h", "--help", "help", "--version", "-V", "version"}


def _print_local_help() -> None:
    sys.stdout.write(
        "SchroSIM Python launcher\n"
        "\n"
        "This package forwards commands to the native `schrosim-cli` runtime.\n"
        "No bundled or PATH `schrosim-cli` backend was found and no local Swift checkout was detected.\n"
        "\n"
        "To run from source:\n"
        "  swift run schrosim-cli --help\n"
    )


def _print_backend_help() -> None:
    sys.stdout.write(
        "SchroSIM Python launcher\n"
        "\n"
        "Bundled/native backend detected.\n"
        "Use subcommands such as:\n"
        "  schrosim version\n"
        "  schrosim info\n"
        "  schrosim run <file>\n"
        "\n"
        "For command details:\n"
        "  schrosim info\n"
    )


def run_cli(args: Sequence[str] | None = None) -> int:
    forwarded_args = list(args if args is not None else sys.argv[1:])

    backend_binary = find_backend_binary()
    if backend_binary is not None:
        if _is_help_or_version(forwarded_args):
            if forwarded_args and forwarded_args[0] in {"--version", "-V", "version"}:
                return _run([str(backend_binary), "version"])
            _print_backend_help()
            return 0
        return _run([str(backend_binary), *forwarded_args])

    repo_root = _find_repo_root(Path.cwd())
    swift = shutil.which("swift")

    if repo_root is not None and swift:
        completed = subprocess.run(
            [swift, "run", "--package-path", str(repo_root), "schrosim-cli", *forwarded_args],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode == 0:
            if completed.stdout:
                sys.stdout.write(completed.stdout)
            if completed.stderr:
                sys.stderr.write(completed.stderr)
            return 0
        if _is_help_or_version(forwarded_args):
            if forwarded_args and forwarded_args[0] in {"--version", "-V", "version"}:
                sys.stdout.write(f"schrosim-python {__version__}\n")
            else:
                _print_local_help()
            return 0
        if completed.stdout:
            sys.stdout.write(completed.stdout)
        if completed.stderr:
            sys.stderr.write(completed.stderr)
        sys.stderr.write("Failed to run local Swift backend (`swift run schrosim-cli`).\n")
        return completed.returncode

    if _is_help_or_version(forwarded_args):
        if forwarded_args and forwarded_args[0] in {"--version", "-V", "version"}:
            sys.stdout.write(f"schrosim-python {__version__}\n")
        else:
            _print_local_help()
        return 0

    sys.stderr.write(
        "SchroSIM CLI backend not found.\n"
        "Install/build `schrosim-cli`, or run from a SchroSIM source checkout with Swift installed.\n"
        "Example:\n"
        "  swift run schrosim-cli --help\n"
    )
    return 1


def main() -> None:
    raise SystemExit(run_cli())
