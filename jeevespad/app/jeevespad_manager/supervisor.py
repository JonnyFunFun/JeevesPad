"""Home Assistant and Supervisor APIs, through the Supervisor proxy."""

from __future__ import annotations

import logging
import os

import aiohttp

_LOGGER = logging.getLogger(__name__)

SUPERVISOR = "http://supervisor"


class Supervisor:
    def __init__(self) -> None:
        self.token = os.environ.get("SUPERVISOR_TOKEN")
        # For development outside Home Assistant: talk to a Home Assistant directly
        self.dev_ha_url = os.environ.get("JEEVES_DEV_HA_URL", "").rstrip("/")
        self.dev_ha_token = os.environ.get("JEEVES_DEV_HA_TOKEN", "")
        self._session: aiohttp.ClientSession | None = None

    @property
    def available(self) -> bool:
        return bool(self.token)

    async def _request(self, method: str, url: str, token: str, json=None):
        if self._session is None:
            self._session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30))
        async with self._session.request(method, url, json=json,
                                         headers={"Authorization": f"Bearer {token}"}) as response:
            response.raise_for_status()
            return await response.json(content_type=None)

    async def close(self) -> None:
        if self._session:
            await self._session.close()

    async def core(self, method: str, path: str, json=None):
        """Home Assistant's REST API (path starts with /api/)."""
        if self.token:
            return await self._request(method, f"{SUPERVISOR}/core{path}", self.token, json)
        if self.dev_ha_url:
            return await self._request(method, f"{self.dev_ha_url}{path}", self.dev_ha_token, json)
        raise RuntimeError("Home Assistant isn't available")

    async def entities(self) -> list[dict]:
        states = await self.core("GET", "/api/states")
        entities = []
        for state in states:
            entity_id = state.get("entity_id", "")
            entities.append({
                "entity_id": entity_id,
                "name": (state.get("attributes") or {}).get("friendly_name") or entity_id,
                "domain": entity_id.split(".", 1)[0],
                "state": state.get("state"),
            })
        return sorted(entities, key=lambda e: e["entity_id"])

    async def suggested_ha_url(self) -> str:
        """Home Assistant's own idea of its local address, for setting up wallPads."""
        try:
            config = await self.core("GET", "/api/config")
            return (config.get("internal_url") or "").rstrip("/")
        except Exception:  # noqa: BLE001 - only a suggestion
            return ""

    async def ingress_port(self) -> int | None:
        if not self.token:
            return None
        info = await self._request("GET", f"{SUPERVISOR}/addons/self/info", self.token)
        return (info.get("data") or {}).get("ingress_port")

    async def announce(self, config: dict) -> None:
        """Lets the JeevesPad integration find this app (Supervisor discovery)."""
        if not self.token:
            return
        try:
            await self._request("POST", f"{SUPERVISOR}/discovery", self.token,
                                {"service": "jeevespad", "config": config})
        except Exception as err:  # noqa: BLE001 - discovery is optional
            _LOGGER.warning("Couldn't announce to Home Assistant: %s", err)
