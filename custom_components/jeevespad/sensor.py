"""wallPad battery level and idle time."""

from __future__ import annotations

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity, SensorStateClass
from homeassistant.const import PERCENTAGE, EntityCategory, UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .coordinator import JeevesPadConfigEntry, JeevesPadCoordinator
from .entity import WallPadEntity, add_entities_for_new_pads

PARALLEL_UPDATES = 0


async def async_setup_entry(hass: HomeAssistant, entry: JeevesPadConfigEntry,
                            async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    coordinator = entry.runtime_data
    entry.async_on_unload(add_entities_for_new_pads(coordinator, async_add_entities, lambda pad_id: [
        BatterySensor(coordinator, pad_id),
        IdleSensor(coordinator, pad_id),
    ]))


class BatterySensor(WallPadEntity, SensorEntity):
    _attr_device_class = SensorDeviceClass.BATTERY
    _attr_native_unit_of_measurement = PERCENTAGE
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "battery")

    @property
    def native_value(self) -> int | None:
        level = self.pad.get("battery")
        return round(level * 100) if isinstance(level, (int, float)) and level >= 0 else None


class IdleSensor(WallPadEntity, SensorEntity):
    """Time since someone last touched the wallPad (updated every poll)."""

    _attr_device_class = SensorDeviceClass.DURATION
    _attr_native_unit_of_measurement = UnitOfTime.SECONDS
    _attr_suggested_unit_of_measurement = UnitOfTime.MINUTES
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "idle_time")

    @property
    def native_value(self) -> int | None:
        idle = self.pad.get("idle_seconds")
        return round(idle) if isinstance(idle, (int, float)) else None
