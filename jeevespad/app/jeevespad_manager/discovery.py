"""Finds running wallPads: every Jeeves advertises _jeeves._tcp over Bonjour."""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field

from zeroconf import IPVersion, ServiceStateChange
from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf

_LOGGER = logging.getLogger(__name__)

SERVICE_TYPE = "_jeeves._tcp.local."


@dataclass
class Advertisement:
    name: str                    # Bonjour instance name: the iPad's name
    host: str                    # IPv4 address
    port: int
    instance_id: str | None      # the app's install ID (TXT "id"; newer versions)
    app_version: str | None
    sync_enabled: bool
    last_seen: float = field(default_factory=time.time)


class Discovery:
    def __init__(self, on_change=None) -> None:
        self._zeroconf: AsyncZeroconf | None = None
        self._browser: AsyncServiceBrowser | None = None
        self._on_change = on_change
        self.advertisements: dict[str, Advertisement] = {}  # by instance name

    async def start(self) -> None:
        self._zeroconf = AsyncZeroconf(ip_version=IPVersion.V4Only)
        self._browser = AsyncServiceBrowser(self._zeroconf.zeroconf, [SERVICE_TYPE], handlers=[self._on_state_change])

    async def stop(self) -> None:
        if self._browser:
            await self._browser.async_cancel()
        if self._zeroconf:
            await self._zeroconf.async_close()

    def _on_state_change(self, zeroconf, service_type: str, name: str, state_change: ServiceStateChange) -> None:
        if state_change is ServiceStateChange.Removed:
            instance = name.removesuffix("." + SERVICE_TYPE)
            if self.advertisements.pop(instance, None) and self._on_change:
                self._on_change()
            return
        asyncio.ensure_future(self._resolve(service_type, name))

    async def _resolve(self, service_type: str, name: str) -> None:
        info = AsyncServiceInfo(service_type, name)
        if not await info.async_request(self._zeroconf.zeroconf, 3000):
            return
        addresses = info.parsed_addresses(IPVersion.V4Only)
        if not addresses or not info.port:
            return

        def prop(key: str) -> str | None:
            value = (info.properties or {}).get(key.encode())
            return value.decode("utf-8", "replace") if value else None

        instance = name.removesuffix("." + SERVICE_TYPE)
        self.advertisements[instance] = Advertisement(
            name=instance,
            host=addresses[0],
            port=info.port,
            instance_id=prop("id"),
            app_version=prop("ver"),
            sync_enabled=prop("sync") == "1",
        )
        _LOGGER.debug("Found wallPad %s at %s:%s", instance, addresses[0], info.port)
        if self._on_change:
            self._on_change()

    async def wait_for(self, predicate, timeout: float) -> Advertisement | None:
        """Waits until an advertisement matching `predicate` appears."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for ad in list(self.advertisements.values()):
                if predicate(ad):
                    return ad
            await asyncio.sleep(1)
        return None
