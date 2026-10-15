"""wallPad connectivity, charging and dimmed state."""

from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .coordinator import JeevesPadConfigEntry, JeevesPadCoordinator
from .entity import WallPadEntity, add_entities_for_new_pads

PARALLEL_UPDATES = 0


async def async_setup_entry(hass: HomeAssistant, entry: JeevesPadConfigEntry,
                            async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    coordinator = entry.runtime_data
    entry.async_on_unload(add_entities_for_new_pads(coordinator, async_add_entities, lambda pad_id: [
        OnlineSensor(coordinator, pad_id),
        ChargingSensor(coordinator, pad_id),
        DimmedSensor(coordinator, pad_id),
        HomeAssistantConnectedSensor(coordinator, pad_id),
    ]))


class OnlineSensor(WallPadEntity, BinarySensorEntity):
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "online")

    @property
    def available(self) -> bool:
        return self.coordinator.last_update_success and self.pad_id in self.coordinator.data

    @property
    def is_on(self) -> bool:
        return bool(self.pad.get("online"))


class ChargingSensor(WallPadEntity, BinarySensorEntity):
    _attr_device_class = BinarySensorDeviceClass.BATTERY_CHARGING

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "charging")

    @property
    def is_on(self) -> bool | None:
        state = self.pad.get("battery_state")
        return None if state in (None, "unknown") else state in ("charging", "full")


class DimmedSensor(WallPadEntity, BinarySensorEntity):
    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "dimmed")

    @property
    def is_on(self) -> bool | None:
        return self.pad.get("dimmed")


class HomeAssistantConnectedSensor(WallPadEntity, BinarySensorEntity):
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "ha_connected")

    @property
    def is_on(self) -> bool | None:
        return self.pad.get("ha_connected")
