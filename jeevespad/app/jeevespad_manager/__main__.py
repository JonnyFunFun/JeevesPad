"""Entry point: python3 -m jeevespad_manager"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal

from aiohttp import web

from .manager import Manager, ManagerError
from .server import create_app

_LOGGER = logging.getLogger("jeevespad_manager")


def load_options(data_dir: str) -> dict:
    try:
        with open(os.path.join(data_dir, "options.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


async def listen_addresses(manager: Manager, dev: bool) -> list[str]:
    """Where to listen. The app is on the host network (for Bonjour), so listen only where
    it's needed: the Supervisor's network (ingress) and localhost (the integration, as Home
    Assistant shares the host network). Not on the LAN."""
    if os.environ.get("JEEVES_BIND"):
        return [a.strip() for a in os.environ["JEEVES_BIND"].split(",") if a.strip()]
    if dev or not manager.supervisor.available or manager.options.get("listen_on_all_addresses"):
        return ["0.0.0.0"]
    return ["127.0.0.1", await manager.supervisor.network_gateway()]


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    data_dir = os.environ.get("JEEVES_DATA", "/data")
    dev = os.environ.get("JEEVES_DEV") == "1"
    os.makedirs(data_dir, exist_ok=True)

    try:
        manager = Manager(data_dir, load_options(data_dir))
    except ManagerError as err:
        _LOGGER.error("%s", err)
        raise SystemExit(1) from err
    port = int(os.environ.get("PORT", "0"))
    if not port:
        try:
            port = await manager.supervisor.ingress_port() or 0
        except Exception as err:  # noqa: BLE001
            _LOGGER.error("Couldn't get the ingress port from the Supervisor: %s", err)
    port = port or 8099

    runner = web.AppRunner(create_app(manager, dev=dev))
    await runner.setup()
    for address in await listen_addresses(manager, dev):
        try:
            await web.TCPSite(runner, address, port).start()
        except OSError as err:
            if address in ("127.0.0.1", "0.0.0.0"):
                raise
            # Shouldn't happen on Home Assistant OS; requests are still checked, so fall back
            _LOGGER.error("Couldn't listen on %s (%s); listening on all addresses instead", address, err)
            await web.TCPSite(runner, "0.0.0.0", port).start()
            break
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
