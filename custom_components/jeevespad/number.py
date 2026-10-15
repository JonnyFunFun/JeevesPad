"""wallPad screen brightness (for example, to dim every panel at night)."""

from __future__ import annotations

from homeassistant.components.number import NumberEntity, NumberMode
from homeassistant.const import PERCENTAGE
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .api import JeevesPadError
from .coordinator import JeevesPadConfigEntry, JeevesPadCoordinator
from .entity import WallPadEntity, add_entities_for_new_pads

PARALLEL_UPDATES = 1


async def async_setup_entry(hass: HomeAssistant, entry: JeevesPadConfigEntry,
                            async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    coordinator = entry.runtime_data
    entry.async_on_unload(add_entities_for_new_pads(coordinator, async_add_entities, lambda pad_id: [
        BrightnessNumber(coordinator, pad_id),
    ]))


class BrightnessNumber(WallPadEntity, NumberEntity):
    _attr_native_min_value = 5
    _attr_native_max_value = 100
    _attr_native_step = 1
    _attr_native_unit_of_measurement = PERCENTAGE
    _attr_mode = NumberMode.SLIDER

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "brightness")

    @property
    def available(self) -> bool:
        return super().available and "command" in (self.pad.get("features") or [])

    @property
    def native_value(self) -> float | None:
        brightness = self.pad.get("brightness")
        return round(brightness * 100) if isinstance(brightness, (int, float)) else None

    async def async_set_native_value(self, value: float) -> None:
        try:
            await self.coordinator.client.command(self.pad_id, "brightness", value / 100)
        except JeevesPadError as err:
            raise HomeAssistantError(str(err)) from err
        self.coordinator.data.get(self.pad_id, {})["brightness"] = value / 100
        self.async_write_ha_state()
