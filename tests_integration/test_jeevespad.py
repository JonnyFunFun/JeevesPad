"""Home Assistant-side tests of the JeevesPad integration (the app's API is mocked)."""

from unittest.mock import AsyncMock, patch

from homeassistant import config_entries
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.helpers.service_info.hassio import HassioServiceInfo
from pytest_homeassistant_custom_component.common import MockConfigEntry

from custom_components.jeevespad.const import CONF_API_KEY, DOMAIN

PADS = [{
    "id": "abcd1234", "name": "Kitchen", "online": True, "host": "10.0.0.5", "app_version": "1.0",
    "model": "iPad2,5", "system_version": "9.3.5", "battery": 0.8, "battery_state": "charging",
    "brightness": 0.6, "dimmed": False, "idle_seconds": 90, "ha_connected": True,
    "features": ["status", "command"], "status_error": None,
}]
DATA = {CONF_HOST: "127.0.0.1", CONF_PORT: 41234, CONF_API_KEY: "key"}
CLIENT = "custom_components.jeevespad.api.JeevesPadClient"


async def test_discovery_flow_and_port_update(hass: HomeAssistant) -> None:
    info = HassioServiceInfo(config={"host": "127.0.0.1", "port": 41234, "api_key": "key"},
                             name="JeevesPad Manager", slug="jeevespad", uuid="1")
    with patch(f"{CLIENT}.wallpads", AsyncMock(return_value=PADS)):
        result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_HASSIO}, data=info)
        assert result["type"] is FlowResultType.FORM and result["step_id"] == "hassio_confirm"
        result = await hass.config_entries.flow.async_configure(result["flow_id"], {})
        assert result["type"] is FlowResultType.CREATE_ENTRY
        await hass.async_block_till_done()

        # The app restarted on another port: the entry follows it
        moved = HassioServiceInfo(config={"host": "127.0.0.1", "port": 45555, "api_key": "key"},
                                  name="JeevesPad Manager", slug="jeevespad", uuid="1")
        result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_HASSIO}, data=moved)
        assert result["type"] is FlowResultType.ABORT
        assert hass.config_entries.async_entries(DOMAIN)[0].data[CONF_PORT] == 45555


async def test_entities_and_actions(hass: HomeAssistant) -> None:
    entry = MockConfigEntry(domain=DOMAIN, data=DATA, unique_id=DOMAIN)
    entry.add_to_hass(hass)
    command = AsyncMock()
    ssh = AsyncMock()
    with patch(f"{CLIENT}.wallpads", AsyncMock(return_value=PADS)), patch(f"{CLIENT}.command", command), \
            patch(f"{CLIENT}.ssh_action", ssh):
        assert await hass.config_entries.async_setup(entry.entry_id)
        await hass.async_block_till_done()

        device_id = er.async_get(hass).async_get("sensor.kitchen_battery").device_id
        device = dr.async_get(hass).async_get(device_id)
        assert (DOMAIN, "abcd1234") in device.identifiers
        assert device.name == "Kitchen" and device.model == "iPad mini" and device.sw_version == "1.0"

        assert hass.states.get("sensor.kitchen_battery").state == "80"
        assert hass.states.get("binary_sensor.kitchen_charging").state == "on"
        assert hass.states.get("binary_sensor.kitchen_jeeves_running").state == "on"
        assert hass.states.get("number.kitchen_screen_brightness").state == "60"

        await hass.services.async_call("number", "set_value",
                                       {"entity_id": "number.kitchen_screen_brightness", "value": 30}, blocking=True)
        command.assert_awaited_with("abcd1234", "brightness", 0.3)
        assert hass.states.get("number.kitchen_screen_brightness").state == "30"

        await hass.services.async_call("button", "press", {"entity_id": "button.kitchen_go_to_home"}, blocking=True)
        command.assert_awaited_with("abcd1234", "home")
        await hass.services.async_call("button", "press", {"entity_id": "button.kitchen_restart_jeeves"}, blocking=True)
        ssh.assert_awaited_with("abcd1234", "restart_app")
