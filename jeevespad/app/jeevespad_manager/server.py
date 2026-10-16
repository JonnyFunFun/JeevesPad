"""Web UI and API.

- The UI and its API (/api/...) are only served to Home Assistant's ingress proxy, which
  has already checked that the user is a Home Assistant administrator.
- /api/v1/... is for the JeevesPad integration and needs the API key it receives via
  Supervisor discovery (wrong keys are throttled).
The app runs on the host network (for Bonjour), so __main__ only listens on the Supervisor's
network and localhost, and everything that isn't one of the above is refused anyway.
Requests that change something need the X-Requested-With header (which pages on other
sites can't send without a CORS preflight, and none is allowed), and responses carry a
strict Content-Security-Policy.
"""

from __future__ import annotations

import hmac
import logging
import os
import time

from aiohttp import web

from .manager import Manager, ManagerError
from .package import PackageError

_LOGGER = logging.getLogger(__name__)

INGRESS_PROXY = "172.30.32.2"
STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
MAX_UPLOAD = 200 * 1024 * 1024
MAX_BODY = 1024 * 1024        # JSON requests; uploads are streamed with their own limit
CSRF_HEADER = "X-Requested-With"
CSRF_VALUE = "jeevespad"
SAFE_METHODS = ("GET", "HEAD", "OPTIONS")
AUTH_FAILURES_ALLOWED = 10    # wrong API keys per address per window, then 429
AUTH_FAILURE_WINDOW = 60.0

SECURITY_HEADERS = {
    "Content-Security-Policy": ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
                                "connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; "
                                "frame-ancestors 'self'"),
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "SAMEORIGIN",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}

MANAGER = web.AppKey("manager", Manager)
DEV = web.AppKey("dev", bool)


def _error(message: str, status: int = 400) -> web.Response:
    return web.json_response({"error": message}, status=status)


class AuthThrottle:
    """Counts wrong API keys per address, to stop guessing."""

    def __init__(self) -> None:
        self._failures: dict[str, list[float]] = {}

    def blocked(self, remote: str) -> bool:
        now = time.monotonic()
        recent = [t for t in self._failures.get(remote, []) if now - t < AUTH_FAILURE_WINDOW]
        if recent:
            self._failures[remote] = recent
        else:
            self._failures.pop(remote, None)
        return len(recent) >= AUTH_FAILURES_ALLOWED

    def failed(self, remote: str) -> None:
        self._failures.setdefault(remote, []).append(time.monotonic())
        if len(self._failures) > 1000:  # don't grow without bound
            self._failures.pop(next(iter(self._failures)))


THROTTLE = web.AppKey("throttle", AuthThrottle)


def _api_key_ok(request: web.Request, api_key: str) -> bool:
    auth = request.headers.get("Authorization", "")
    return hmac.compare_digest(auth.encode("utf-8", "replace"), f"Bearer {api_key}".encode())


def _from_ingress(request: web.Request) -> bool:
    # The ingress proxy's address, and the header it adds to every request it forwards
    return request.remote == INGRESS_PROXY and "X-Ingress-Path" in request.headers


def _same_site(request: web.Request) -> bool:
    """Requests that change something must come from this page, not another site."""
    if request.method in SAFE_METHODS:
        return True
    if request.headers.get(CSRF_HEADER) != CSRF_VALUE:
        return False
    return request.headers.get("Sec-Fetch-Site", "same-origin") in ("same-origin", "none")


@web.middleware
async def access_control(request: web.Request, handler):
    manager: Manager = request.app[MANAGER]
    remote = request.remote or ""
    if request.path.startswith("/api/v1/"):
        throttle = request.app[THROTTLE]
        if throttle.blocked(remote):
            return _error("Too many attempts; try again later", 429)
        if not _api_key_ok(request, manager.api_key):
            throttle.failed(remote)
            _LOGGER.warning("Rejected an integration API request from %s (wrong API key)", remote)
            return _error("Unauthorized", 401)
    else:
        if not request.app[DEV] and not _from_ingress(request):
            return _error("Forbidden", 403)
        if request.path.startswith("/api/") and not _same_site(request):
            return _error("Forbidden", 403)
    try:
        return await handler(request)
    except (ManagerError, PackageError) as err:
        return _error(str(err))
    except web.HTTPException:
        raise
    except Exception:  # noqa: BLE001
        # Details go to the log, not to the client
        _LOGGER.exception("Request %s %s failed", request.method, request.path)
        return _error("Unexpected error; see the app's log", 500)


async def _security_headers(request: web.Request, response: web.StreamResponse) -> None:
    for name, value in SECURITY_HEADERS.items():
        response.headers.setdefault(name, value)
    if request.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"


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

def _asset_version() -> str:
    """Changes whenever the UI files do, so browsers don't keep an old copy after an update."""
    return str(max(int(os.path.getmtime(os.path.join(STATIC_DIR, name))) for name in os.listdir(STATIC_DIR)))


async def index(request: web.Request) -> web.Response:
    with open(os.path.join(STATIC_DIR, "index.html")) as f:
        html = f.read()
    version = _asset_version()
    for asset in ("static/app.js", "static/style.css", "static/theme.js"):
        html = html.replace(f'"{asset}"', f'"{asset}?v={version}"')
    return web.Response(text=html, content_type="text/html", headers={"Cache-Control": "no-cache"})


async def state(request: web.Request) -> web.Response:
    m: Manager = request.app[MANAGER]
    return web.json_response({
        "fleet_code": m.fleet_code,
        "fleet_code_generated": m.fleet_code_is_generated,
        "default_password": m.ssh_password == "alpine",
        "wallpad_ha_url": m.options.get("wallpad_ha_url") or await m.supervisor.suggested_ha_url(),
        "has_wallpad_token": bool(m.options.get("wallpad_ha_token")),
        "guided_access_code_set": m.unlock_code is not None,
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


async def enroll(request: web.Request) -> web.Response:
    data = await _json(request)
    job = request.app[MANAGER].enroll(request.match_info["id"], data.get("password") or None,
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


async def guided_access(request: web.Request) -> web.Response:
    data = await _json(request)
    pad = await request.app[MANAGER].set_guided_access(request.match_info["id"], bool(data.get("on")))
    return web.json_response(pad.public())


async def maintenance(request: web.Request) -> web.Response:
    data = await _json(request)
    pad = await request.app[MANAGER].set_maintenance(request.match_info["id"], data.get("on"), data.get("message"))
    return web.json_response(pad.public())


async def guided_access_code(request: web.Request) -> web.Response:
    data = await _json(request)
    results = await request.app[MANAGER].set_unlock_code(data.get("code"))
    return web.json_response({"results": results})


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
        "guided_access": status.get("guidedAccess"), "guided_access_error": status.get("guidedAccessError") or None,
        "maintenance": status.get("maintenance"),
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
    app = web.Application(middlewares=[access_control], client_max_size=MAX_BODY)
    app[MANAGER] = manager
    app[DEV] = dev
    app[THROTTLE] = AuthThrottle()
    app.on_response_prepare.append(_security_headers)
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
    app.router.add_post("/api/wallpads/{id}/enroll", enroll)
    app.router.add_post("/api/copy-settings", copy_settings)
    app.router.add_post("/api/provision", provision)
    app.router.add_post("/api/update-app", update_app)
    app.router.add_post("/api/wallpads/{id}/guided-access", guided_access)
    app.router.add_post("/api/wallpads/{id}/maintenance", maintenance)
    app.router.add_post("/api/guided-access-code", guided_access_code)
    app.router.add_get("/api/jobs/{id}", get_job)
    app.router.add_get("/api/entities", entities)
    app.router.add_post("/api/package/upload", upload_package)
    app.router.add_post("/api/package/download", download_package)
    app.router.add_delete("/api/package/custom", remove_custom_package)
    app.router.add_get("/api/v1/wallpads", v1_wallpads)
    app.router.add_post("/api/v1/wallpads/{id}/command", v1_command)
    app.router.add_post("/api/v1/wallpads/{id}/ssh/{action}", v1_ssh)
    app.router.add_post("/api/v1/wallpads/{id}/guided-access", guided_access)
    app.router.add_post("/api/v1/wallpads/{id}/maintenance", maintenance)
    return app
