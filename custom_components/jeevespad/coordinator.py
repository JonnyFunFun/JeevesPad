"""Polls the JeevesPad Manager app for wallPad status."""

from __future__ import annotations

import logging

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ConfigEntryAuthFailed
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .api import JeevesPadAuthError, JeevesPadClient, JeevesPadError
from .const import DOMAIN, SCAN_INTERVAL

_LOGGER = logging.getLogger(__name__)

type JeevesPadConfigEntry = ConfigEntry[JeevesPadCoordinator]


class JeevesPadCoordinator(DataUpdateCoordinator[dict[str, dict]]):
    """wallPads by ID."""

    config_entry: JeevesPadConfigEntry

    def __init__(self, hass: HomeAssistant, entry: JeevesPadConfigEntry, client: JeevesPadClient) -> None:
        super().__init__(hass, _LOGGER, config_entry=entry, name=DOMAIN, update_interval=SCAN_INTERVAL)
        self.client = client

    async def _async_update_data(self) -> dict[str, dict]:
        try:
            pads = await self.client.wallpads()
        except JeevesPadAuthError as err:
            raise ConfigEntryAuthFailed(str(err)) from err
        except JeevesPadError as err:
            raise UpdateFailed(str(err)) from err
        return {pad["id"]: pad for pad in pads}
