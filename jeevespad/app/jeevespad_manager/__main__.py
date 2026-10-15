"""Entry point: python3 -m jeevespad_manager"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal

from aiohttp import web

from .manager import Manager
from .server import create_app

_LOGGER = logging.getLogger("jeevespad_manager")


def load_options(data_dir: str) -> dict:
    try:
        with open(os.path.join(data_dir, "options.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    data_dir = os.environ.get("JEEVES_DATA", "/data")
    dev = os.environ.get("JEEVES_DEV") == "1"
    os.makedirs(data_dir, exist_ok=True)

    manager = Manager(data_dir, load_options(data_dir))
    port = int(os.environ.get("PORT", "0"))
    if not port:
        try:
            port = await manager.supervisor.ingress_port() or 0
        except Exception as err:  # noqa: BLE001
            _LOGGER.error("Couldn't get the ingress port from the Supervisor: %s", err)
    port = port or 8099

    runner = web.AppRunner(create_app(manager, dev=dev))
    await runner.setup()
    await web.TCPSite(runner, "0.0.0.0", port).start()
    await manager.start()
    _LOGGER.info("JeevesPad Manager listening on port %s (fleet code %s)", port,
                 "generated" if manager.fleet_code_is_generated else "from configuration")
    # The JeevesPad integration runs in Home Assistant, which shares the host network
    await manager.supervisor.announce({"host": "127.0.0.1", "port": port, "api_key": manager.api_key})

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()
    await manager.stop()
    await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())
