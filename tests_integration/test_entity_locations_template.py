"""The JeevesPad Manager app looks up entity areas and devices with a template
(supervisor.LOCATIONS_TEMPLATE); check it renders in Home Assistant's template engine."""

import importlib.util
import json
import pathlib

from homeassistant.core import HomeAssistant
from homeassistant.helpers import area_registry as ar, device_registry as dr, entity_registry as er
from homeassistant.helpers.template import Template
from pytest_homeassistant_custom_component.common import MockConfigEntry

SUPERVISOR_PY = pathlib.Path(__file__).parents[1] / "jeevespad/app/jeevespad_manager/supervisor.py"


def _template() -> str:
    spec = importlib.util.spec_from_file_location("jeevespad_supervisor", SUPERVISOR_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.LOCATIONS_TEMPLATE


async def test_locations_template(hass: HomeAssistant) -> None:
    entry = MockConfigEntry(domain="test")
    entry.add_to_hass(hass)
    kitchen = ar.async_get(hass).async_create("Kitchen")
    device = dr.async_get(hass).async_get_or_create(config_entry_id=entry.entry_id, identifiers={("test", "lamp")},
                                                    name="Hue Lamp", suggested_area="Kitchen")
    dr.async_get(hass).async_update_device(device.id, area_id=kitchen.id, name_by_user="Counter Lamp")
    er.async_get(hass).async_get_or_create("light", "test", "lamp1", device_id=device.id, suggested_object_id="counter")
    hass.states.async_set("light.counter", "on", {"friendly_name": "Counter"})
    hass.states.async_set("sensor.loose", "21", {"friendly_name": "Loose sensor"})

    rows = json.loads(Template(_template(), hass).async_render(parse_result=False))
    by_id = {row[0]: row for row in rows}
    assert by_id["light.counter"] == ["light.counter", "Kitchen", "Counter Lamp"]
    assert by_id["sensor.loose"] == ["sensor.loose", "", ""]
