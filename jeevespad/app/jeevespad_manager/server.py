"""Web UI and API.

- The UI and its API (/api/...) are only served to Home Assistant's ingress proxy, which
  has already checked that the user is a Home Assistant administrator.
- /api/v1/... is for the JeevesPad integration and needs the API key it receives via
  Supervisor discovery.
The app runs on the host network (for Bonjour), so everything else is refused.
"""

from __future__ import annotations

import hmac
import logging
import os

from aiohttp import web

from .manager import Manager, ManagerError
from .package import PackageError

_LOGGER = logging.getLogger(__name__)

INGRESS_PROXY = "172.30.32.2"
STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
MAX_UPLOAD = 200 * 1024 * 1024

MANAGER = web.AppKey("manager", Manager)
DEV = web.AppKey("dev", bool)


def _error(message: str, status: int = 400) -> web.Response:
    return web.json_response({"error": message}, status=status)


@web.middleware
async def access_control(request: web.Request, handler):
    manager: Manager = request.app[MANAGER]
    if request.path.startswith("/api/v1/"):
        auth = request.headers.get("Authorization", "")
        if not hmac.compare_digest(auth.encode(), f"Bearer {manager.api_key}".encode()):
            return _error("Unauthorized", 401)
    elif not request.app[DEV] and request.remote != INGRESS_PROXY:
        return _error("Forbidden", 403)
    try:
        return await handler(request)
    except (ManagerError, PackageError) as err:
        return _error(str(err))
    except web.HTTPException:
        raise
    except Exception as err:  # noqa: BLE001 - show the problem in the UI
        _LOGGER.exception("Request %s %s failed", request.method, request.path)
        return _error(f"Unexpected error: {err}", 500)


async def _json(request: web.Request) -> dict:
    try:
        data = await request.json()
    except ValueError as err:
        raise ManagerError("Invalid request") from err
    if not isinstance(data, dict):
        raise ManagerError("Invalid request")
    return data


def _job(job) -> dict:
    return {"id": job.id, "title": job.title, "state": job.state, "log": job.log,
            "error": job.error, "result": job.result, "created": job.created}


# --- UI ------------------------------------------------------------------------------

async def index(request: web.Request) -> web.Response:
    response = web.FileResponse(os.path.join(STATIC_DIR, "index.html"))
    response.headers["Cache-Control"] = "no-cache"
    return response


async def state(request: web.Request) -> web.Response:
    m: Manager = request.app[MANAGER]
    return web.json_response({
        "fleet_code": m.fleet_code,
        "fleet_code_generated": m.fleet_code_is_generated,
        "default_password": m.ssh_password == "alpine",
        "wallpad_ha_url": m.options.get("wallpad_ha_url") or await m.supervisor.suggested_ha_url(),
        "has_wallpad_token": bool(m.options.get("wallpad_ha_token")),
        "package": m.package.info(),
        "wallpads": m.list_pads(),
        "jobs": sorted((_job(j) for j in m.jobs.values()), key=lambda j: -j["created"])[:10],
    })


async def wallpads(request: web.Request) -> web.Response:
    return web.json_response(request.app[MANAGER].list_pads())


async def add_wallpad(request: web.Request) -> web.Response:
    data = await _json(request)
    pad = request.app[MANAGER].add_manual(data.get("host") or "", data.get("name"))
    return web.json_response(pad.public())


async def update_wallpad(request: web.Request) -> web.Response:
    pad = request.app[MANAGER].update_pad(request.match_info["id"], await _json(request))
    return web.json_response(pad.public())


async def remove_wallpad(request: web.Request) -> web.Response:
    request.app[MANAGER].remove(request.match_info["id"])
    return web.json_response({"ok": True})


async def refresh(request: web.Request) -> web.Response:
    pad = await request.app[MANAGER].refresh_status(request.match_info["id"])
    return web.json_response(pad.public())


async def get_settings(request: web.Request) -> web.Response:
    view = await request.app[MANAGER].get_settings(request.match_info["id"])
    view.pop("_other_card_settings", None)
    return web.json_response(view)


async def put_settings(request: web.Request) -> web.Response:
    data = await _json(request)
    sections = data.get("sections")
    if not isinstance(sections, list) or not sections:
        raise ManagerError("Nothing to save")
    m: Manager = request.app[MANAGER]
    targets = data.get("also") or []
    await m.save_settings(request.match_info["id"], data.get("settings") or {}, sections)
    results = {}
    if targets:
        results = await m.copy_settings(request.match_info["id"], targets, sections)
    return web.json_response({"ok": True, "copied": results})


async def command(request: web.Request) -> web.Response:
    data = await _json(request)
    await request.app[MANAGER].command(request.match_info["id"], data.get("command") or "", data.get("value"))
    return web.json_response({"ok": True})


async def ssh_action(request: web.Request) -> web.Response:
    data = await _json(request) if request.can_read_body else {}
    result = await request.app[MANAGER].ssh_action(request.match_info["id"], request.match_info["action"],
                                                     data.get("password") or None)
    return web.json_response({"ok": True, "result": result})


async def enrol(request: web.Request) -> web.Response:
    data = await _json(request)
    job = request.app[MANAGER].enrol(request.match_info["id"], data.get("password") or None,
                                       data.get("settings_source") or None)
    return web.json_response(_job(job))


async def copy_settings(request: web.Request) -> web.Response:
    data = await _json(request)
    results = await request.app[MANAGER].copy_settings(data.get("source") or "", data.get("targets") or [],
                                                         data.get("sections") or None)
    return web.json_response({"results": results})


async def provision(request: web.Request) -> web.Response:
    data = await _json(request)
    job = request.app[MANAGER].provision(data.get("host") or "", data.get("password") or None,
                                           data.get("settings_source") or None,
                                           data.get("ha_url") or None, data.get("ha_token") or None)
    return web.json_response(_job(job))


async def update_app(request: web.Request) -> web.Response:
    data = await _json(request)
    job = request.app[MANAGER].update_app(data.get("wallpads") or [])
    return web.json_response(_job(job))


async def get_job(request: web.Request) -> web.Response:
    job = request.app[MANAGER].jobs.get(request.match_info["id"])
    if job is None:
        return _error("Unknown job", 404)
    return web.json_response(_job(job))


async def entities(request: web.Request) -> web.Response:
    try:
        return web.json_response(await request.app[MANAGER].supervisor.entities())
    except Exception as err:  # noqa: BLE001
        raise ManagerError(f"Couldn't load entities from Home Assistant: {err}") from err


async def upload_package(request: web.Request) -> web.Response:
    reader = await request.multipart()
    part = await reader.next()
    if part is None or part.name != "file":
        raise ManagerError("Choose a Jeeves.ipa file")
    data = bytearray()
    while chunk := await part.read_chunk(65536):
        data.extend(chunk)
        if len(data) > MAX_UPLOAD:
            raise ManagerError("That file is too large to be a Jeeves package")
    m: Manager = request.app[MANAGER]
    m.upload_package(bytes(data), part.filename or "upload")
    return web.json_response(m.package.info())


async def remove_custom_package(request: web.Request) -> web.Response:
    m: Manager = request.app[MANAGER]
    m.remove_custom_package()
    return web.json_response(m.package.info())


async def download_package(request: web.Request) -> web.Response:
    data = await _json(request)
    m: Manager = request.app[MANAGER]
    await m.download_package(data.get("url"))
    return web.json_response(m.package.info())


# --- integration API ---------------------------------------------------------------------

def _integration_pad(pad: dict) -> dict:
    status = pad.get("status") or {}
    return {
        "id": pad["id"], "name": pad["name"], "online": pad["online"], "host": pad["address"],
        "app_version": status.get("appVersion") or pad.get("app_version"),
        "model": status.get("model"), "system_version": status.get("systemVersion"),
        "battery": status.get("battery"), "battery_state": status.get("batteryState"),
        "brightness": status.get("brightness"), "dimmed": status.get("dimmed"),
        "idle_seconds": status.get("idleSeconds"), "ha_connected": status.get("haConnected"),
        "features": status.get("features") or [], "status_error": pad.get("status_error"),
    }


async def v1_wallpads(request: web.Request) -> web.Response:
    return web.json_response([_integration_pad(p) for p in request.app[MANAGER].list_pads()])


async def v1_command(request: web.Request) -> web.Response:
    return await command(request)


async def v1_ssh(request: web.Request) -> web.Response:
    if request.match_info["action"] not in ("restart_app", "reboot"):
        return _error("Not allowed", 403)
    return await ssh_action(request)


def create_app(manager: Manager, dev: bool = False) -> web.Application:
    app = web.Application(middlewares=[access_control], client_max_size=MAX_UPLOAD + 1024 * 1024)
    app[MANAGER] = manager
    app[DEV] = dev
    app.router.add_get("/", index)
    app.router.add_static("/static/", STATIC_DIR)
    app.router.add_get("/api/state", state)
    app.router.add_get("/api/wallpads", wallpads)
    app.router.add_post("/api/wallpads", add_wallpad)
    app.router.add_patch("/api/wallpads/{id}", update_wallpad)
    app.router.add_delete("/api/wallpads/{id}", remove_wallpad)
    app.router.add_post("/api/wallpads/{id}/refresh", refresh)
    app.router.add_get("/api/wallpads/{id}/settings", get_settings)
    app.router.add_put("/api/wallpads/{id}/settings", put_settings)
    app.router.add_post("/api/wallpads/{id}/command", command)
    app.router.add_post("/api/wallpads/{id}/ssh/{action}", ssh_action)
    app.router.add_post("/api/wallpads/{id}/enrol", enrol)
    app.router.add_post("/api/copy-settings", copy_settings)
    app.router.add_post("/api/provision", provision)
    app.router.add_post("/api/update-app", update_app)
    app.router.add_get("/api/jobs/{id}", get_job)
    app.router.add_get("/api/entities", entities)
    app.router.add_post("/api/package/upload", upload_package)
    app.router.add_post("/api/package/download", download_package)
    app.router.add_delete("/api/package/custom", remove_custom_package)
    app.router.add_get("/api/v1/wallpads", v1_wallpads)
    app.router.add_post("/api/v1/wallpads/{id}/command", v1_command)
    app.router.add_post("/api/v1/wallpads/{id}/ssh/{action}", v1_ssh)
    return app
