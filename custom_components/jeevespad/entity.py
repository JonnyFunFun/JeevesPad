"""Base entity: one Home Assistant device per wallPad."""

from __future__ import annotations

from collections.abc import Callable

from homeassistant.core import callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity import Entity
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import JeevesPadCoordinator

MODELS = {
    "iPad2,1": "iPad 2", "iPad2,2": "iPad 2", "iPad2,3": "iPad 2", "iPad2,4": "iPad 2",
    "iPad2,5": "iPad mini", "iPad2,6": "iPad mini", "iPad2,7": "iPad mini",
    "iPad3,1": "iPad (3rd generation)", "iPad3,4": "iPad (4th generation)",
    "iPad4,1": "iPad Air", "iPad4,2": "iPad Air", "iPad4,4": "iPad mini 2", "iPad4,5": "iPad mini 2", "iPad4,7": "iPad mini 3",
}


class WallPadEntity(CoordinatorEntity[JeevesPadCoordinator]):
    _attr_has_entity_name = True

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str, key: str) -> None:
        super().__init__(coordinator)
        self.pad_id = pad_id
        self._attr_unique_id = f"{pad_id}_{key}"
        self._attr_translation_key = key
        pad = self.pad
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, pad_id)},
            name=pad.get("name") or "wallPad",
            manufacturer="Apple",
            model=MODELS.get(pad.get("model") or "", pad.get("model")),
            sw_version=pad.get("app_version"),
            hw_version=f"iOS {pad['system_version']}" if pad.get("system_version") else None,
        )

    @property
    def pad(self) -> dict:
        return self.coordinator.data.get(self.pad_id) or {}

    @property
    def available(self) -> bool:
        # Status values come from Jeeves itself, so need it running and reachable
        return super().available and bool(self.pad.get("online")) and not self.pad.get("status_error")


def add_entities_for_new_pads(coordinator: JeevesPadCoordinator, async_add_entities,
                              make: Callable[[str], list[Entity]]) -> Callable[[], None]:
    """Adds entities for each wallPad now, and for wallPads that appear later."""
    known: set[str] = set()

    @callback
    def add_new() -> None:
        new = [pad_id for pad_id in coordinator.data if pad_id not in known]
        if not new:
            return
        known.update(new)
        async_add_entities([entity for pad_id in new for entity in make(pad_id)])

    add_new()
    return coordinator.async_add_listener(add_new)
