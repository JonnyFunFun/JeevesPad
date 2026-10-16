"""JeevesPad: Jeeves wall panels (wallPads) as Home Assistant devices.

Talks to the JeevesPad Manager app, which finds the wallPads and relays commands.
"""

from __future__ import annotations

from homeassistant.const import CONF_HOST, CONF_PORT, Platform
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .api import JeevesPadClient
from .const import CONF_API_KEY
from .coordinator import JeevesPadConfigEntry, JeevesPadCoordinator

PLATFORMS = [Platform.BINARY_SENSOR, Platform.BUTTON, Platform.NUMBER, Platform.SENSOR, Platform.SWITCH]


async def async_setup_entry(hass: HomeAssistant, entry: JeevesPadConfigEntry) -> bool:
    client = JeevesPadClient(async_get_clientsession(hass), entry.data[CONF_HOST], entry.data[CONF_PORT],
                             entry.data[CONF_API_KEY])
    coordinator = JeevesPadCoordinator(hass, entry, client)
    await coordinator.async_config_entry_first_refresh()
    entry.runtime_data = coordinator
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: JeevesPadConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
