from __future__ import annotations

import sysconfig
from pathlib import Path
from typing import Any

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


class CustomBuildHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict[str, Any]) -> None:
        if self.target_name != "wheel":
            return

        backend = Path(self.root) / "src" / "schrosim" / "_bin" / "schrosim-cli"
        if not backend.is_file():
            return

        platform_tag = sysconfig.get_platform().replace("-", "_").replace(".", "_")
        build_data["pure_python"] = False
        build_data["tag"] = f"py3-none-{platform_tag}"
