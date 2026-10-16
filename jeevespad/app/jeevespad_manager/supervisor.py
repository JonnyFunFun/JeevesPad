"""Home Assistant and Supervisor APIs, through the Supervisor proxy."""

from __future__ import annotations

import json
import logging
import os

import aiohttp

_LOGGER = logging.getLogger(__name__)

SUPERVISOR = "http://supervisor"
DEFAULT_GATEWAY = "172.30.32.1"

# [[entity_id, area name, device name], ...] for every entity, in one template render
LOCATIONS_TEMPLATE = (
    "{%- set ns = namespace(rows=[]) -%}"
    "{%- for s in states -%}"
    "{%- set ns.rows = ns.rows + [[s.entity_id, area_name(s.entity_id) or '', "
    "device_attr(s.entity_id, 'name_by_user') or device_attr(s.entity_id, 'name') or '']] -%}"
    "{%- endfor -%}"
    "{{ ns.rows | tojson }}"
)


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
        """Every entity, with what the entity pickers need to search and filter."""
        states = await self.core("GET", "/api/states")
        locations = await self._entity_locations()
        entities = []
        for state in states:
            entity_id = state.get("entity_id", "")
            attributes = state.get("attributes") or {}
            area, device = locations.get(entity_id, ("", ""))
            entities.append({
                "entity_id": entity_id,
                "name": attributes.get("friendly_name") or entity_id,
                "domain": entity_id.split(".", 1)[0],
                "state": state.get("state"),
                "unit": attributes.get("unit_of_measurement") or "",
                "device_class": attributes.get("device_class") or "",
                "area": area,
                "device": device,
            })
        return sorted(entities, key=lambda e: e["entity_id"])

    async def _entity_locations(self) -> dict[str, tuple[str, str]]:
        """Area and device names by entity ID. The REST API doesn't include them, but a
        template can look them all up in one request. Optional: {} if that fails."""
        try:
            rendered = await self.core_text("POST", "/api/template", {"template": LOCATIONS_TEMPLATE})
            rows = json.loads(rendered)
            return {row[0]: (row[1] or "", row[2] or "") for row in rows if isinstance(row, list) and len(row) == 3}
        except Exception as err:  # noqa: BLE001
            _LOGGER.info("Couldn't look up entity areas: %s", err)
            return {}

    async def core_text(self, method: str, path: str, json_body=None) -> str:
        """Like core(), for endpoints that answer with text (such as /api/template)."""
        if self.token:
            url, token = f"{SUPERVISOR}/core{path}", self.token
        elif self.dev_ha_url:
            url, token = f"{self.dev_ha_url}{path}", self.dev_ha_token
        else:
            raise RuntimeError("Home Assistant isn't available")
        if self._session is None:
            self._session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30))
        async with self._session.request(method, url, json=json_body, headers={"Authorization": f"Bearer {token}"}) as response:
            response.raise_for_status()
            return await response.text()

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

    async def network_gateway(self) -> str:
        """The host's address on the Supervisor's network, where ingress connects to apps
        on the host network (the "hassio" Docker network's gateway)."""
        try:
            info = await self._request("GET", f"{SUPERVISOR}/network/info", self.token)
            gateway = ((info.get("data") or {}).get("docker") or {}).get("gateway")
            if gateway:
                return gateway
        except Exception as err:  # noqa: BLE001
            _LOGGER.debug("Couldn't read the Supervisor network: %s", err)
        return DEFAULT_GATEWAY

    async def announce(self, config: dict) -> None:
        """Lets the JeevesPad integration find this app (Supervisor discovery)."""
        if not self.token:
            return
        try:
            await self._request("POST", f"{SUPERVISOR}/discovery", self.token,
                                {"service": "jeevespad", "config": config})
        except Exception as err:  # noqa: BLE001 - discovery is optional
            _LOGGER.warning("Couldn't announce to Home Assistant: %s", err)
