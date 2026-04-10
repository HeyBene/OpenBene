from __future__ import annotations

import importlib
import sys


SDK_INSTALL_HINT = "python3 -m pip install -e /path/to/OpenBene/openbene_sdk"
PILLOW_INSTALL_HINT = "python3 -m pip install pillow"


def run_sdk_bridge(module_name: str, label: str) -> int:
    try:
        module = importlib.import_module(module_name)
    except ModuleNotFoundError as exc:
        missing = exc.name or str(exc)
        if missing == "PIL":
            print(f"{label} requires Pillow.", file=sys.stderr)
            print("Refresh the local SDK dependencies with:", file=sys.stderr)
            print(f"  {SDK_INSTALL_HINT}", file=sys.stderr)
            print("Or install Pillow directly with:", file=sys.stderr)
            print(f"  {PILLOW_INSTALL_HINT}", file=sys.stderr)
            return 1
        if missing == "openbene" or missing.startswith("openbene."):
            print(f"{label} requires the local OpenBene SDK.", file=sys.stderr)
            print("Install it with:", file=sys.stderr)
            print(f"  {SDK_INSTALL_HINT}", file=sys.stderr)
            return 1
        print(f"{label} failed to import dependency '{missing}': {exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"{label} failed to start: {exc}", file=sys.stderr)
        return 1

    bridge_main = getattr(module, "main", None)
    if bridge_main is None:
        print(
            f"{label} is unavailable because module '{module_name}' does not expose a main() entry point.",
            file=sys.stderr,
        )
        return 1

    try:
        result = bridge_main()
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"{label} failed while running: {exc}", file=sys.stderr)
        return 1

    return 0 if result is None else int(result)
