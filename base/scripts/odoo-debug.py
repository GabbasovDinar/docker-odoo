#!/usr/bin/env python3

import os
import sys

import debugpy

os.environ["TZ"] = "UTC"

TRUE_VALUES = {"1", "true", "yes", "on"}


def env_bool(name: str) -> bool:
    return os.getenv(name, "").strip().lower() in TRUE_VALUES


def main() -> None:
    host = os.getenv("DEBUGPY_HOST", "0.0.0.0")
    port = int(os.getenv("DEBUGPY_PORT", "5678"))

    debugpy.listen((host, port))
    print(f"[debugpy] listening on {host}:{port}", file=sys.stderr, flush=True)

    if env_bool("DEBUGPY_WAIT_FOR_CLIENT"):
        print("[debugpy] waiting for debugger client...", file=sys.stderr, flush=True)
        debugpy.wait_for_client()

    import odoo.cli

    odoo.cli.main()


if __name__ == "__main__":
    main()
