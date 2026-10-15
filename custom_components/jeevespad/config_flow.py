"""Config flow: set up automatically when the JeevesPad Manager app announces itself."""

from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.service_info.hassio import HassioServiceInfo

from .api import JeevesPadAuthError, JeevesPadClient, JeevesPadError
from .const import CONF_API_KEY, DOMAIN


class JeevesPadConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._discovered: dict[str, Any] = {}

    async def _validate(self, data: dict[str, Any]) -> str | None:
        client = JeevesPadClient(async_get_clientsession(self.hass), data[CONF_HOST], data[CONF_PORT], data[CONF_API_KEY])
        try:
            await client.wallpads()
        except JeevesPadAuthError:
            return "invalid_auth"
        except JeevesPadError:
            return "cannot_connect"
        return None

    async def async_step_hassio(self, discovery_info: HassioServiceInfo) -> ConfigFlowResult:
        """The app announced itself (it does on every start; its port can change)."""
        config = discovery_info.config
        self._discovered = {CONF_HOST: config["host"], CONF_PORT: int(config["port"]), CONF_API_KEY: config["api_key"]}
        await self.async_set_unique_id(DOMAIN)
        self._abort_if_unique_id_configured(updates=self._discovered)
        return await self.async_step_hassio_confirm()

    async def async_step_hassio_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        if user_input is not None:
            error = await self._validate(self._discovered)
            if error is None:
                return self.async_create_entry(title="wallPads", data=self._discovered)
            errors["base"] = error
        return self.async_show_form(step_id="hassio_confirm", errors=errors)

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Manual setup, for when discovery isn't available."""
        await self.async_set_unique_id(DOMAIN)
        self._abort_if_unique_id_configured()
        errors: dict[str, str] = {}
        if user_input is not None:
            error = await self._validate(user_input)
            if error is None:
                return self.async_create_entry(title="wallPads", data=user_input)
            errors["base"] = error
        schema = vol.Schema({
            vol.Required(CONF_HOST, default="127.0.0.1"): str,
            vol.Required(CONF_PORT): int,
            vol.Required(CONF_API_KEY): str,
        })
        return self.async_show_form(step_id="user", data_schema=schema, errors=errors)
