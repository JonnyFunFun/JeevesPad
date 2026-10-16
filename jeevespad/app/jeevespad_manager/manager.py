"""Keeps track of wallPads and runs everything the app does to them.

Two channels reach a wallPad:
- In-app (the fleet protocol, fleet.py): status, settings and commands. Needs Jeeves
  running with fleet sync on and the same fleet code, and finds it with Bonjour.
- SSH (ssh.py): installing and updating Jeeves, enrolling it into the fleet, restarting,
  rebooting and logs. Works whenever the iPad is reachable, even without Jeeves.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import plistlib
import secrets
import time
import uuid
from dataclasses import asdict, dataclass, field
from typing import Any, Awaitable, Callable

from . import fleet, settings
from .discovery import Advertisement, Discovery
from .hosts import InvalidHost, normalize_host
from .package import DEFAULT_URL, PackageError, PackageStore
from .ssh import PROVISION_PATH, SSHClient, SSHError
from .supervisor import Supervisor

_LOGGER = logging.getLogger(__name__)

STATUS_INTERVAL = 60
# Remote commands Jeeves understands ("guided_access" has its own method)
COMMANDS = ("home", "reload", "wake", "identify", "brightness")
MIN_FLEET_CODE = 8
MAX_MAINTENANCE_MESSAGE = 500
MAX_WALLPADS = 200  # anything on the network can advertise itself; don't let it fill the list
GUIDED_ACCESS_CODE_KEY = "JeevesGuidedAccessCode"
GUIDED_ACCESS_WAIT = 6  # seconds to wait for iOS to start or end Guided Access
WAIT_FOR_APP = 90  # seconds to wait for a freshly installed Jeeves to advertise itself
MAX_JOBS = 30


@dataclass
class WallPad:
    id: str
    name: str
    # Addresses. Bonjour can be spoofed by anything on the network, so an advertised
    # address (seen_host) is only used for fleet requests, which are authenticated. It
    # becomes `host`, and is used for SSH (which sends the root password), once the iPad
    # there has answered a fleet request, proving it has the fleet code.
    host: str | None = None          # last verified address
    ssh_host: str | None = None      # set by hand, or the address it was set up at
    ssh_password: str | None = None  # if it differs from the app's root password option
    added: float = field(default_factory=time.time)
    # Not persisted
    port: int | None = None
    seen_host: str | None = None     # address Bonjour advertises (not yet trusted for SSH)
    online: bool = False
    app_version: str | None = None
    sync_enabled: bool | None = None
    status: dict | None = None
    status_error: str | None = None
    status_at: float | None = None

    PERSISTED = ("id", "name", "host", "ssh_host", "ssh_password", "added")

    @property
    def address(self) -> str | None:
        return self.ssh_host or self.host

    def public(self) -> dict:
        data = {k: v for k, v in asdict(self).items() if k != "ssh_password"}
        data["has_ssh_password"] = bool(self.ssh_password)
        data["address"] = self.address
        return data


@dataclass
class Job:
    id: str
    title: str
    state: str = "running"  # running, done, failed
    log: list = field(default_factory=list)
    error: str | None = None
    result: Any = None
    created: float = field(default_factory=time.time)

    def add(self, line: str) -> None:
        _LOGGER.info("[%s] %s", self.title, line)
        self.log.append({"t": time.time(), "line": line})


class ManagerError(Exception):
    pass


def generate_fleet_code() -> str:
    alphabet = "abcdefghjkmnpqrstuvwxyz23456789"  # no look-alike characters, easy to type on an iPad
    return "-".join("".join(secrets.choice(alphabet) for _ in range(4)) for _ in range(4))


class Manager:
    def __init__(self, data_dir: str, options: dict) -> None:
        self.data_dir = data_dir
        self.options = options
        self.store_path = os.path.join(data_dir, "wallpads.json")
        self.wallpads: dict[str, WallPad] = {}
        self.jobs: dict[str, Job] = {}
        self.package = PackageStore(data_dir)
        self._installs = 0  # jobs that are installing a package right now
        self.ssh = SSHClient(os.path.join(data_dir, "known_hosts"))
        self.supervisor = Supervisor()
        self.discovery = Discovery(on_change=self._discovery_changed)
        self._host_locks: dict[str, asyncio.Lock] = {}
        self._tasks: set[asyncio.Task] = set()
        self.fleet_code = self._load_fleet_code()
        self.api_key = self._load_secret("api_key")
        self.unlock_code_path = os.path.join(data_dir, "guided_access_code")
        self._load_store()
        for host in options.get("extra_hosts") or []:
            try:
                self.add_manual(host, save=False)
            except ManagerError as err:
                _LOGGER.error("Ignoring extra wallPad address: %s", err)

    # --- configuration --------------------------------------------------------------

    def _load_secret(self, name: str) -> str:
        path = os.path.join(self.data_dir, name)
        try:
            with open(path) as f:
                value = f.read().strip()
            if value:
                return value
        except OSError:
            pass
        value = secrets.token_urlsafe(32)
        with open(path, "w") as f:
            f.write(value)
        os.chmod(path, 0o600)
        return value

    def _load_fleet_code(self) -> str:
        configured = (self.options.get("fleet_code") or "").strip()
        if configured:
            if len(configured) < MIN_FLEET_CODE:
                # It's the key to every wallPad's settings (including Home Assistant tokens),
                # and a captured request could be used to guess a short one offline
                raise ManagerError(f"The fleet code must be at least {MIN_FLEET_CODE} characters. Change it in the "
                                   "app's configuration, or leave it empty to have one generated.")
            return configured
        path = os.path.join(self.data_dir, "fleet_code")
        try:
            with open(path) as f:
                code = f.read().strip()
            if code:
                return code
        except OSError:
            pass
        code = generate_fleet_code()
        with open(path, "w") as f:
            f.write(code)
        os.chmod(path, 0o600)
        return code

    @property
    def fleet_code_is_generated(self) -> bool:
        return not (self.options.get("fleet_code") or "").strip()

    @property
    def ssh_password(self) -> str:
        return self.options.get("ssh_password") or "alpine"

    # --- persistence ----------------------------------------------------------------

    def _load_store(self) -> None:
        try:
            with open(self.store_path) as f:
                stored = json.load(f)
        except (OSError, ValueError):
            return
        for item in stored.get("wallpads", []):
            try:
                pad = WallPad(**{k: item.get(k) for k in WallPad.PERSISTED if k in item})
            except TypeError:
                continue
            self.wallpads[pad.id] = pad

    def save(self) -> None:
        data = {"wallpads": [{k: getattr(p, k) for k in WallPad.PERSISTED} for p in self.wallpads.values()]}
        tmp = self.store_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=1)
        os.chmod(tmp, 0o600)
        os.replace(tmp, self.store_path)

    # --- lifecycle ------------------------------------------------------------------

    async def start(self) -> None:
        await self.discovery.start()
        self._spawn(self._status_loop())

    async def stop(self) -> None:
        for task in list(self._tasks):
            task.cancel()
        await self.discovery.stop()
        await self.supervisor.close()

    def _spawn(self, coro: Awaitable) -> asyncio.Task:
        task = asyncio.ensure_future(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return task

    async def _status_loop(self) -> None:
        while True:
            await asyncio.sleep(STATUS_INTERVAL)
            await self.refresh_all()

    async def refresh_all(self) -> None:
        pads = [p for p in self.wallpads.values() if p.online]
        await asyncio.gather(*(self.refresh_status(p.id) for p in pads), return_exceptions=True)

    # --- wallPad registry -----------------------------------------------------------

    def _discovery_changed(self) -> None:
        changed = False
        seen = set()
        for ad in list(self.discovery.advertisements.values()):
            pad = self._pad_for_advertisement(ad)
            seen.add(pad.id)
            first_sighting = not pad.online
            if pad.name != ad.name:
                changed = True
            pad.name, pad.seen_host, pad.port = ad.name, ad.host, ad.port
            pad.online, pad.app_version, pad.sync_enabled = True, ad.app_version, ad.sync_enabled
            if first_sighting:
                self._spawn(self.refresh_status(pad.id))
        for pad in self.wallpads.values():
            if pad.id not in seen and pad.online:
                pad.online, pad.port = False, None
        if changed:
            self.save()

    def _pad_for_advertisement(self, ad: Advertisement) -> WallPad:
        pad_id = ad.instance_id or f"name:{ad.name}"
        pad = self.wallpads.get(pad_id)
        if pad is None:
            if len(self.wallpads) >= MAX_WALLPADS:
                _LOGGER.warning("Ignoring %s: already tracking %d wallPads", ad.name, MAX_WALLPADS)
                return WallPad(id=pad_id, name=ad.name)  # not kept
            pad = WallPad(id=pad_id, name=ad.name)
            # Fold in an entry for the same iPad added by address, or seen before the app
            # advertised its install ID
            for other in list(self.wallpads.values()):
                if other.id in (f"host:{ad.host}", f"name:{ad.name}") and not other.online:
                    pad.ssh_host = pad.ssh_host or other.ssh_host
                    pad.ssh_password = pad.ssh_password or other.ssh_password
                    pad.added = min(pad.added, other.added)
                    del self.wallpads[other.id]
            self.wallpads[pad_id] = pad
            self.save()
        return pad

    def add_manual(self, host: str, name: str | None = None, save: bool = True) -> WallPad:
        try:
            host = normalize_host(host)
        except InvalidHost as err:
            raise ManagerError(str(err)) from err
        for pad in self.wallpads.values():
            if host in (pad.host, pad.ssh_host):
                return pad
        pad = WallPad(id=f"host:{host}", name=name or host, host=host, ssh_host=host)
        self.wallpads[pad.id] = pad
        if save:
            self.save()
        return pad

    def get(self, pad_id: str) -> WallPad:
        pad = self.wallpads.get(pad_id)
        if pad is None:
            raise ManagerError("Unknown wallPad")
        return pad

    def remove(self, pad_id: str) -> None:
        self.wallpads.pop(pad_id, None)
        self.save()

    def update_pad(self, pad_id: str, data: dict) -> WallPad:
        pad = self.get(pad_id)
        if "ssh_host" in data:
            value = (data.get("ssh_host") or "").strip()
            try:
                pad.ssh_host = normalize_host(value) if value else None
            except InvalidHost as err:
                raise ManagerError(str(err)) from err
        if "ssh_password" in data:
            pad.ssh_password = data.get("ssh_password") or None
        self.save()
        return pad

    def list_pads(self) -> list[dict]:
        return [p.public() for p in sorted(self.wallpads.values(), key=lambda p: p.name.lower())]

    # --- in-app channel -------------------------------------------------------------

    async def _fleet(self, pad: WallPad, rtype: str, payload: dict | None = None) -> dict:
        if not pad.online or not pad.port or not pad.seen_host:
            raise ManagerError(f"{pad.name} isn't running Jeeves on the network right now")
        try:
            response = await fleet.request(pad.seen_host, pad.port, self.fleet_code, rtype, payload, device_name=pad.name)
            if pad.host != pad.seen_host and pad.id in self.wallpads:
                # It answered with the fleet code: this address really is this wallPad
                pad.host = pad.seen_host
                self.save()
            return response
        except fleet.FleetError as err:
            message = str(err)
            if "turned off" in message or "different fleet code" in message:
                message += ". Enroll it (over SSH) or set this fleet code in Settings → Fleet on the iPad."
            raise ManagerError(message) from err

    async def refresh_status(self, pad_id: str) -> WallPad:
        pad = self.get(pad_id)
        try:
            response = await self._fleet(pad, "status")
            pad.status = response.get("status") if isinstance(response.get("status"), dict) else {}
            pad.status_error = None
        except ManagerError as err:
            # Older versions of Jeeves don't know "status" but still share settings
            pad.status_error = "This version of Jeeves can't report its status; update it" \
                if "Unknown request" in str(err) else str(err)
        pad.status_at = time.time()
        return pad

    def _features(self, pad: WallPad) -> list:
        return (pad.status or {}).get("features") or []

    async def get_settings(self, pad_id: str) -> dict:
        pad = self.get(pad_id)
        response = await self._fleet(pad, "pull")
        snapshot = response.get("settings")
        if not isinstance(snapshot, dict):
            raise ManagerError(f"{pad.name} didn't send its settings")
        return settings.to_view(snapshot)

    async def save_settings(self, pad_id: str, view: dict, sections: list[str]) -> None:
        pad = self.get(pad_id)
        current = await self.get_settings(pad_id)
        if "dashboards" in sections and not current["dashboards"]["rooms_editable"]:
            # Never send rooms to a version that can't read them (it would drop its rooms)
            view = dict(view, dashboards=dict(view.get("dashboards") or {}, rooms=None))
        try:
            snapshot = settings.from_view(view, sections, current)
        except settings.InvalidSettings as err:
            raise ManagerError(str(err)) from err
        if "rooms" not in snapshot and "JeevesRooms" in snapshot["keys"]:
            snapshot["keys"].remove("JeevesRooms")
        await self._push(pad, snapshot)

    async def _push(self, pad: WallPad, snapshot: dict) -> None:
        response = await self._fleet(pad, "push", {"settings": snapshot})
        if not response.get("ok"):
            raise ManagerError(f"{pad.name} didn't accept the settings")

    async def copy_settings(self, source_id: str, target_ids: list[str], sections: list[str] | None) -> dict:
        """Copies settings from one wallPad to others (all shared settings, or `sections`)."""
        source = self.get(source_id)
        response = await self._fleet(source, "pull")
        snapshot = response.get("settings")
        if not isinstance(snapshot, dict):
            raise ManagerError(f"{source.name} didn't send its settings")
        if sections:
            wanted = set()
            for section in sections:
                wanted.update(settings.SECTION_KEYS.get(section, []))
                if section == "connection":
                    wanted.add("HAAccessToken")
                if section == "dashboards":
                    wanted.add("JeevesRooms")
            snapshot = {"keys": [k for k in snapshot.get("keys", []) if k in wanted],
                        "values": {k: v for k, v in (snapshot.get("values") or {}).items() if k in wanted},
                        **({"rooms": snapshot["rooms"]} if "dashboards" in sections and "rooms" in snapshot else {})}

        results = {}
        for target_id in target_ids:
            if target_id == source_id:
                continue
            target = self.get(target_id)
            try:
                await self._push(target, snapshot)
                results[target_id] = None
            except ManagerError as err:
                results[target_id] = str(err)
        return results

    # --- Guided Access ----------------------------------------------------------------

    @property
    def unlock_code(self) -> str | None:
        """The code that ends Guided Access on wallPads (a shared Jeeves setting)."""
        try:
            with open(self.unlock_code_path) as f:
                return f.read().strip() or None
        except OSError:
            return None

    async def set_unlock_code(self, code: str | None) -> dict:
        """Saves the unlock code (for new wallPads too) and sends it to every wallPad."""
        code = (code or "").strip() or None
        if code is not None and not code.isdigit():
            raise ManagerError("The unlock code must be digits only (it's typed on a number pad)")
        if code is None:
            if os.path.exists(self.unlock_code_path):
                os.remove(self.unlock_code_path)
        else:
            with open(self.unlock_code_path, "w") as f:
                f.write(code)
            os.chmod(self.unlock_code_path, 0o600)

        snapshot = {"keys": [GUIDED_ACCESS_CODE_KEY], "values": {GUIDED_ACCESS_CODE_KEY: code} if code else {}}
        results: dict[str, str | None] = {}
        for pad in [p for p in self.wallpads.values() if p.online]:
            if "guided_access" not in self._features(pad):
                results[pad.id] = "Needs a newer version of Jeeves"
                continue
            try:
                await self._push(pad, snapshot)
                results[pad.id] = None
            except ManagerError as err:
                results[pad.id] = str(err)
        return results

    async def set_guided_access(self, pad_id: str, on: bool) -> WallPad:
        """Starts or ends Guided Access, and waits to see whether iOS allowed it."""
        pad = self.get(pad_id)
        if "guided_access" not in self._features(pad):
            await self.refresh_status(pad_id)
            if "guided_access" not in self._features(pad):
                raise ManagerError(f"{pad.name} needs a newer version of Jeeves for Guided Access")
        await self._fleet(pad, "command", {"command": "guided_access", "value": on})
        for _ in range(GUIDED_ACCESS_WAIT):
            await asyncio.sleep(1)
            await self.refresh_status(pad_id)
            status = pad.status or {}
            if status.get("guidedAccess") == on:
                return pad
            if status.get("guidedAccessError"):
                raise ManagerError(status["guidedAccessError"])
        raise ManagerError(f"{pad.name} didn't {'start' if on else 'end'} Guided Access")

    async def set_maintenance(self, pad_id: str, on: bool, message: str | None = None) -> WallPad:
        """Locks the wallPad behind a maintenance notice, or unlocks it."""
        if not isinstance(on, bool):
            raise ManagerError("Say whether maintenance mode should be on or off")
        if message is not None and not isinstance(message, str):
            raise ManagerError("The maintenance message must be text")
        message = (message or "").strip()
        if len(message) > MAX_MAINTENANCE_MESSAGE:
            raise ManagerError(f"Keep the maintenance message under {MAX_MAINTENANCE_MESSAGE} characters")
        pad = self.get(pad_id)
        if "maintenance" not in self._features(pad):
            await self.refresh_status(pad_id)
            if "maintenance" not in self._features(pad):
                raise ManagerError(f"{pad.name} needs a newer version of Jeeves for maintenance mode")
        value: dict[str, Any] = {"on": on}
        if message:
            value["message"] = message
        await self._fleet(pad, "command", {"command": "maintenance", "value": value})
        await self.refresh_status(pad_id)
        if (pad.status or {}).get("maintenance") != on:
            raise ManagerError(f"{pad.name} didn't {'start' if on else 'end'} maintenance mode")
        return pad

    async def command(self, pad_id: str, command: str, value: Any = None) -> None:
        if command not in COMMANDS:
            raise ManagerError(f"Unknown command {command!r}")
        if command == "brightness":
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= 1:
                raise ManagerError("Brightness must be a number from 0 to 1")
            value = float(value)
        else:
            value = None
        pad = self.get(pad_id)
        if "command" not in self._features(pad):
            await self.refresh_status(pad_id)
            if "command" not in self._features(pad):
                raise ManagerError(f"{pad.name} needs a newer version of Jeeves for remote commands")
        payload = {"command": command}
        if value is not None:
            payload["value"] = value
        await self._fleet(pad, "command", payload)

    # --- SSH channel ----------------------------------------------------------------

    def _lock(self, host: str) -> asyncio.Lock:
        return self._host_locks.setdefault(host, asyncio.Lock())

    def _ssh_target(self, pad: WallPad, password: str | None = None) -> tuple[str, str]:
        if not pad.address:
            raise ManagerError(f"{pad.name} has no known address")
        return pad.address, password or pad.ssh_password or self.ssh_password

    async def ssh_action(self, pad_id: str, action: str, password: str | None = None) -> Any:
        pad = self.get(pad_id)
        host, pw = self._ssh_target(pad, password)
        async with self._lock(host):
            try:
                if action == "restart_app":
                    await self.ssh.restart_app(host, pw)
                elif action == "reboot":
                    await self.ssh.reboot(host, pw)
                elif action == "respring":
                    await self.ssh.respring(host, pw)
                elif action == "logs":
                    return await self.ssh.fetch_logs(host, pw)
                elif action == "check":
                    return await self.ssh.tools_report(host, pw)
                elif action == "forget_host_key":
                    await self.ssh.forget_host_key(host)
                else:
                    raise ManagerError(f"Unknown action {action}")
            except SSHError as err:
                raise ManagerError(str(err)) from err
        if password and password != pad.ssh_password and password != self.ssh_password:
            pad.ssh_password = password  # it worked: remember it for this wallPad
            self.save()
        return None

    # --- jobs -------------------------------------------------------------------------

    def start_job(self, title: str, work: Callable[[Job], Awaitable[Any]]) -> Job:
        job = Job(id=uuid.uuid4().hex[:12], title=title)
        self.jobs[job.id] = job
        for old in sorted(self.jobs.values(), key=lambda j: j.created)[:-MAX_JOBS]:
            if old.state != "running":
                del self.jobs[old.id]

        async def runner():
            try:
                job.result = await work(job)
                job.state = "done"
                job.add("Done.")
            except (ManagerError, SSHError, PackageError) as err:
                job.state, job.error = "failed", str(err)
                job.add(f"Failed: {err}")
            except Exception as err:  # noqa: BLE001 - report anything to the user
                _LOGGER.exception("Job %s failed", title)
                job.state, job.error = "failed", f"Unexpected error: {err}"
                job.add(job.error)

        self._spawn(runner())
        return job

    async def _ensure_package(self, job: Job) -> str:
        if not self.package.active():
            url = self.options.get("app_package_url") or DEFAULT_URL
            job.add(f"No app package yet; downloading {url}…")
            meta = await self.package.download(url)
            job.add(f"Downloaded Jeeves {meta['version']} ({meta['build']}).")
        app_dir = self.package.install_ready()
        job.add(f"Installing {self.package.describe_active()}.")
        return app_dir

    def _installing(self, work: Callable[[Job], Awaitable[Any]]) -> Callable[[Job], Awaitable[Any]]:
        """Marks a job as installing, so packages aren't replaced while it copies one."""
        async def wrapped(job: Job):
            self._installs += 1
            try:
                return await work(job)
            finally:
                self._installs -= 1
        return wrapped

    def _check_not_installing(self) -> None:
        if self._installs:
            raise ManagerError("Jeeves is being installed on a wallPad right now. Try again when that's finished.")

    def upload_package(self, data: bytes, filename: str) -> dict:
        """Stores the user's own package; it's used instead of the published one."""
        self._check_not_installing()
        return self.package.upload(data, filename)

    def remove_custom_package(self) -> None:
        """Goes back to the published package."""
        self._check_not_installing()
        self.package.remove_custom()

    async def download_package(self, url: str | None) -> dict:
        self._check_not_installing()
        return await self.package.download((url or self.options.get("app_package_url") or DEFAULT_URL).strip())

    async def _provision_payload(self, job: Job, settings_source: str | None, ha_url: str | None,
                                 ha_token: str | None) -> dict:
        provision: dict[str, Any] = {"fleetEnabled": True, "fleetCode": self.fleet_code, "from": "Home Assistant"}
        if settings_source and settings_source.startswith("copy:"):
            source = self.get(settings_source[5:])
            job.add(f"Copying settings from {source.name}…")
            response = await self._fleet(source, "pull")
            if isinstance(response.get("settings"), dict):
                provision["settings"] = response["settings"]
        elif settings_source == "ha":
            url = (ha_url or self.options.get("wallpad_ha_url") or "").strip()
            token = (ha_token or self.options.get("wallpad_ha_token") or "").strip()
            if not url or not token:
                raise ManagerError("Enter the Home Assistant URL and access token for the wallPad "
                                   "(or set them in the app's configuration)")
            provision["settings"] = settings.connection_snapshot(url, token)
        code = self.unlock_code
        if code:
            snapshot = provision.setdefault("settings", {"keys": [], "values": {}})
            if GUIDED_ACCESS_CODE_KEY not in snapshot["keys"]:
                snapshot["keys"].append(GUIDED_ACCESS_CODE_KEY)
            snapshot["values"][GUIDED_ACCESS_CODE_KEY] = code
        return provision

    async def _write_provision(self, host: str, password: str, provision: dict) -> None:
        data = plistlib.dumps(fleet._plist_safe(provision), fmt=plistlib.FMT_BINARY)
        await self.ssh.write_file(host, password, PROVISION_PATH, data)

    def provision(self, host: str, password: str | None, settings_source: str | None,
                  ha_url: str | None = None, ha_token: str | None = None) -> Job:
        """Installs Jeeves on a newly jailbroken iPad and adds it to the fleet."""
        try:
            host = normalize_host(host)
        except InvalidHost as err:
            raise ManagerError(str(err)) from err
        pw = password or self.ssh_password

        async def work(job: Job):
            async with self._lock(host):
                job.add(f"Connecting to {host} over SSH…")
                try:
                    await self.ssh.check_login(host, pw)
                except SSHError as err:
                    if err.code == 5 and not password:
                        raise ManagerError(f"{host} rejected the root password. Enter its password and try again.") from err
                    raise
                tools = await self.ssh.tools_report(host, pw)
                job.add(f"Connected: {tools.get('model') or 'iPad'}, iOS {tools.get('ios') or '?'}.")
                if tools.get("ios", "").split(".")[0] not in ("9", ""):
                    job.add(f"Note: Jeeves is made for iOS 9; this iPad has iOS {tools.get('ios')}.")

                app_dir = await self._ensure_package(job)
                provision = await self._provision_payload(job, settings_source, ha_url, ha_token)
                await self.ssh.install_app(host, pw, app_dir, job.add)
                job.add("Saving the fleet settings for Jeeves to pick up when it starts…")
                await self._write_provision(host, pw, provision)
                job.add("Starting Jeeves…")
                await self.ssh.launch_app(host, pw)

            job.add("Waiting for Jeeves to appear on the network…")
            ad = await self.discovery.wait_for(lambda a: a.host == host, WAIT_FOR_APP)
            if ad is None:
                pad = self.add_manual(host)
                job.add("Jeeves didn't appear yet. It's installed; open it on the iPad if it isn't running.")
            else:
                self._discovery_changed()
                pad = self._pad_for_advertisement(ad)
                await self.refresh_status(pad.id)
                job.add(f"{pad.name} is up and in the fleet.")
            pad.ssh_host = host
            if password and password != self.ssh_password:
                pad.ssh_password = password
            self.save()
            return {"wallpad": pad.id}

        return self.start_job(f"Set up {host}", self._installing(work))

    def enroll(self, pad_id: str, password: str | None, settings_source: str | None) -> Job:
        """Adds a wallPad that already runs Jeeves to the fleet: sets its fleet code over SSH."""
        pad = self.get(pad_id)
        host, pw = self._ssh_target(pad, password)

        async def work(job: Job):
            provision = await self._provision_payload(job, settings_source, None, None)
            async with self._lock(host):
                job.add(f"Connecting to {host} over SSH…")
                await self.ssh.check_login(host, pw)
                await self._write_provision(host, pw, provision)
                job.add("Restarting Jeeves to apply the fleet settings…")
                await self.ssh.restart_app(host, pw)
            if password:
                pad.ssh_password = password
                self.save()
            job.add("Waiting for Jeeves to come back…")
            await asyncio.sleep(5)
            if pad.online:
                await self.refresh_status(pad.id)
            return {"wallpad": pad.id}

        return self.start_job(f"Enroll {pad.name}", work)

    def update_app(self, pad_ids: list[str]) -> Job:
        """Installs the current app package on wallPads (settings are kept)."""
        pads = [self.get(i) for i in pad_ids]
        if not pads:
            raise ManagerError("Choose at least one wallPad")

        async def work(job: Job):
            app_dir = await self._ensure_package(job)
            failures = []
            for pad in pads:
                job.add(f"— {pad.name} —")
                try:
                    host, pw = self._ssh_target(pad)
                    async with self._lock(host):
                        await self.ssh.install_app(host, pw, app_dir, job.add)
                        await self.ssh.launch_app(host, pw)
                    job.add(f"Updated {pad.name}.")
                except (ManagerError, SSHError) as err:
                    failures.append(f"{pad.name}: {err}")
                    job.add(f"Couldn't update {pad.name}: {err}")
            if failures:
                raise ManagerError(f"Updated {len(pads) - len(failures)} of {len(pads)} wallPads")
            return {"updated": len(pads)}

        return self.start_job("Update Jeeves" if len(pads) > 1 else f"Update {pads[0].name}", self._installing(work))
