"""wallPad actions: identify, go Home, reload, restart Jeeves."""

from __future__ import annotations

from homeassistant.components.button import ButtonDeviceClass, ButtonEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .api import JeevesPadError
from .coordinator import JeevesPadConfigEntry, JeevesPadCoordinator
from .entity import WallPadEntity, add_entities_for_new_pads

PARALLEL_UPDATES = 1

# key, command sent to Jeeves (or "ssh:<action>"), device class, category
BUTTONS = (
    ("identify", "identify", ButtonDeviceClass.IDENTIFY, EntityCategory.DIAGNOSTIC),
    ("go_home", "home", None, None),
    ("wake", "wake", None, None),
    ("reload", "reload", None, EntityCategory.DIAGNOSTIC),
    ("restart_app", "ssh:restart_app", ButtonDeviceClass.RESTART, EntityCategory.DIAGNOSTIC),
)


async def async_setup_entry(hass: HomeAssistant, entry: JeevesPadConfigEntry,
                            async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    coordinator = entry.runtime_data
    entry.async_on_unload(add_entities_for_new_pads(coordinator, async_add_entities, lambda pad_id: [
        WallPadButton(coordinator, pad_id, *spec) for spec in BUTTONS
    ]))


class WallPadButton(WallPadEntity, ButtonEntity):
    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str, key: str, command: str,
                 device_class: ButtonDeviceClass | None, category: EntityCategory | None) -> None:
        super().__init__(coordinator, pad_id, key)
        self._command = command
        self._attr_device_class = device_class
        self._attr_entity_category = category

    @property
    def available(self) -> bool:
        if self._command.startswith("ssh:"):
            # Works over SSH, even when Jeeves isn't running
            return self.coordinator.last_update_success and bool(self.pad.get("host"))
        return super().available and "command" in (self.pad.get("features") or [])

    async def async_press(self) -> None:
        try:
            if self._command.startswith("ssh:"):
                await self.coordinator.client.ssh_action(self.pad_id, self._command[4:])
            else:
                await self.coordinator.client.command(self.pad_id, self._command)
        except JeevesPadError as err:
            raise HomeAssistantError(str(err)) from err
        await self.coordinator.async_request_refresh()
