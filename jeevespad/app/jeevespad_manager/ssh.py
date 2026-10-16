"""SSH side channel to wallPads (jailbroken iPads): the same commands as deploy_common.sh.

Uses ssh/scp through sshpass, with the password in the environment (`sshpass -e`) so it
never appears in the process list. iOS 9 jailbreaks ship an old OpenSSH with RSA host
keys, hence the ssh-rsa options. Host keys are remembered on first use
(/data/known_hosts); a changed key is reported instead of silently accepted.
"""

from __future__ import annotations

import asyncio
import logging
import os
import shlex
from dataclasses import dataclass

from .hosts import InvalidHost, is_ipv6, normalize_host

_LOGGER = logging.getLogger(__name__)

APP_PATH = "/Applications/Jeeves.app"
PROVISION_PATH = "/var/mobile/Library/Jeeves/provision.plist"
LAUNCH = "open com.jeeves.Jeeves 2>/dev/null || uiopen /Applications/Jeeves.app 2>/dev/null || uiopen jeeves://"

# Installs the Cydia packages installing Jeeves needs, if they're missing: uikittools
# (uicache: adds the app to the home screen) and com.conradkramer.open (open: starts Jeeves
# remotely). Keep in sync with JEEVES_DEPENDENCIES_SCRIPT in deploy_common.sh.
DEPENDENCIES_SCRIPT = """missing=""
command -v uicache >/dev/null 2>&1 || missing="$missing uikittools"
command -v open >/dev/null 2>&1 || missing="$missing com.conradkramer.open"
if [ -z "$missing" ]; then echo "deps=ok"; exit 0; fi
command -v apt-get >/dev/null 2>&1 || { echo "deps=noapt$missing"; exit 3; }
echo "Installing$missing from Cydia..."
apt-get update >/dev/null 2>&1
apt-get install -y --force-yes $missing 2>&1 | tail -3
command -v uicache >/dev/null 2>&1 || { echo "deps=failed uikittools"; exit 4; }
command -v open >/dev/null 2>&1 || echo "deps=warn com.conradkramer.open"
exit 0"""

# sshpass exit codes
WRONG_PASSWORD = 5
HOST_KEY_CHANGED = 6


class SSHError(Exception):
    def __init__(self, message: str, code: int | None = None) -> None:
        super().__init__(message)
        self.code = code


@dataclass
class Result:
    code: int
    stdout: str
    stderr: str


class SSHClient:
    def __init__(self, known_hosts: str, connect_timeout: int = 10) -> None:
        self.known_hosts = known_hosts
        self.connect_timeout = connect_timeout

    def _options(self) -> list[str]:
        return [
            "-o", "HostKeyAlgorithms=+ssh-rsa",
            "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", f"UserKnownHostsFile={self.known_hosts}",
            "-o", f"ConnectTimeout={self.connect_timeout}",
            "-o", "LogLevel=ERROR",
        ]

    async def _exec(self, args: list[str], password: str, timeout: float, stdin: bytes | None = None) -> Result:
        env = dict(os.environ, SSHPASS=password)
        proc = await asyncio.create_subprocess_exec(
            "sshpass", "-e", *args, env=env,
            stdin=asyncio.subprocess.PIPE if stdin is not None else asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        try:
            out, err = await asyncio.wait_for(proc.communicate(stdin), timeout)
        except asyncio.TimeoutError as exc:
            proc.kill()
            await proc.wait()
            raise SSHError("The wallPad took too long to respond") from exc
        return Result(proc.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace"))

    @staticmethod
    def _checked(host: str) -> str:
        # Last line of defence: never pass anything but an address to ssh/scp
        try:
            return normalize_host(host)
        except InvalidHost as err:
            raise SSHError(str(err)) from err

    @staticmethod
    def _check(result: Result, host: str) -> Result:
        if result.code == 0:
            return result
        if result.code == WRONG_PASSWORD:
            raise SSHError(f"{host} rejected the root password", WRONG_PASSWORD)
        if result.code == HOST_KEY_CHANGED or "HOST IDENTIFICATION HAS CHANGED" in result.stderr:
            raise SSHError(f"{host}'s SSH host key has changed (was the iPad restored or re-jailbroken?). "
                           "Forget its host key if that's expected.", HOST_KEY_CHANGED)
        detail = (result.stderr.strip() or result.stdout.strip()).splitlines()
        raise SSHError(f"{host}: {detail[-1] if detail else f'ssh exit code {result.code}'}", result.code)

    async def run(self, host: str, password: str, command: str, timeout: float = 60, check: bool = True,
                  stdin: bytes | None = None) -> Result:
        host = self._checked(host)
        args = ["ssh", *self._options(), f"root@{host}", command]
        result = await self._exec(args, password, timeout, stdin)
        return self._check(result, host) if check else result

    async def copy_to(self, host: str, password: str, local: str, remote: str, timeout: float = 600) -> None:
        host = self._checked(host)
        target = f"[{host}]" if is_ipv6(host) else host
        args = ["scp", *self._options(), "-r", "--", local, f"root@{target}:{remote}"]
        self._check(await self._exec(args, password, timeout), host)

    async def write_file(self, host: str, password: str, remote: str, data: bytes, mode: str = "600",
                         owner: str = "mobile:mobile") -> None:
        """Writes `data` to a file on the wallPad (through ssh's stdin, so no temp files)."""
        directory = os.path.dirname(remote)
        command = (f"mkdir -p {shlex.quote(directory)} && chown {owner} {shlex.quote(directory)} && "
                   f"cat > {shlex.quote(remote)} && chmod {mode} {shlex.quote(remote)} && "
                   f"chown {owner} {shlex.quote(remote)}")
        await self.run(host, password, command, stdin=data)

    async def check_login(self, host: str, password: str) -> None:
        await self.run(host, password, "true", timeout=30)

    async def forget_host_key(self, host: str) -> None:
        host = self._checked(host)
        proc = await asyncio.create_subprocess_exec(
            "ssh-keygen", "-R", host, "-f", self.known_hosts,
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await proc.wait()

    # --- wallPad maintenance --------------------------------------------------------

    async def ensure_dependencies(self, host: str, password: str, log) -> None:
        """Installs missing Cydia packages that installing Jeeves needs."""
        log("Checking Cydia packages…")
        result = await self.run(host, password, DEPENDENCIES_SCRIPT, check=False, timeout=600)
        if result.code == WRONG_PASSWORD:
            self._check(result, host)
        for line in result.stdout.splitlines():
            if line.strip() and not line.startswith("deps="):
                log(line.strip())
        if result.code == 3:
            missing = result.stdout.split("deps=noapt", 1)[-1].split()
            raise SSHError(f"{host} is missing Cydia packages ({', '.join(missing)}) and has no apt-get to install them")
        if result.code == 4:
            raise SSHError("Couldn't install UIKit Tools (uikittools) on the iPad. Install it from Cydia, then try again.")
        if result.code != 0:
            self._check(result, host)
        if "deps=warn" in result.stdout:
            log("Note: couldn't install Open (com.conradkramer.open), so Jeeves can't be started remotely. "
                "Start it from the home screen.")

    async def install_app(self, host: str, password: str, app_dir: str, log) -> None:
        """Installs Payload/Jeeves.app (deploy_common.sh's jeeves_install)."""
        await self.ensure_dependencies(host, password, log)
        log("Stopping Jeeves if it's running…")
        await self.run(host, password, "killall Jeeves 2>/dev/null || true")
        log("Removing the old HomeButler app if present…")
        await self.run(host, password,
                       "if [ -d /Applications/HomeButler.app ]; then killall HomeButler 2>/dev/null; "
                       "rm -rf /Applications/HomeButler.app && uicache; fi; rm -rf /Applications/Jeeves.app")
        # Start from an empty app folder: scp won't create it (the iPad's SFTP server can't
        # resolve a target that doesn't exist yet), and removing it clears out old files
        await self.run(host, password, f"mkdir -p {APP_PATH}")
        log("Copying the app to the iPad…")
        await self.copy_to(host, password, app_dir, "/Applications/")
        log("Setting permissions and refreshing the home screen…")
        await self.run(host, password,
                       f"chmod -R 755 {APP_PATH} && chown -R root:wheel {APP_PATH} && uicache -p {APP_PATH} || uicache",
                       timeout=180)

    async def launch_app(self, host: str, password: str) -> None:
        await self.run(host, password, LAUNCH, check=False)

    async def restart_app(self, host: str, password: str) -> None:
        await self.run(host, password, f"killall Jeeves 2>/dev/null; sleep 1; {LAUNCH}", check=False)

    async def reboot(self, host: str, password: str) -> None:
        # The connection drops as the iPad goes down, so don't treat that as failure
        await self.run(host, password, "(sleep 1; reboot) >/dev/null 2>&1 &", check=False, timeout=20)

    async def respring(self, host: str, password: str) -> None:
        await self.run(host, password, "killall -9 SpringBoard", check=False)

    async def tools_report(self, host: str, password: str) -> dict:
        """Which of the tools installing needs are present on the iPad."""
        script = ("for t in uicache open uiopen killall; do "
                  "if command -v $t >/dev/null 2>&1; then echo \"$t=1\"; else echo \"$t=0\"; fi; done; "
                  "echo \"ios=$(grep -A1 '<key>ProductVersion</key>' /System/Library/CoreServices/SystemVersion.plist "
                  "2>/dev/null | tail -1 | sed 's/<[^>]*>//g' | tr -d '[:space:]')\"; "
                  "echo \"model=$(sysctl -n hw.machine 2>/dev/null)\"; "
                  "echo \"installed=$([ -d /Applications/Jeeves.app ] && echo 1 || echo 0)\"")
        result = await self.run(host, password, script)
        report = {}
        for line in result.stdout.splitlines():
            key, _, value = line.partition("=")
            report[key.strip()] = value.strip()
        return report

    async def fetch_logs(self, host: str, password: str) -> dict:
        logs = "/var/mobile/Library/Logs"
        script = (f"echo '=== Last uncaught exception ==='; cat {logs}/Jeeves-exception.log 2>/dev/null || echo '(none)'; "
                  f"echo; echo '=== Last phone pairing ==='; cat {logs}/Jeeves-pairing.log 2>/dev/null || echo '(none)'; "
                  f"echo; echo '=== Crash and memory reports ==='; "
                  f"ls -lt {logs}/CrashReporter/ 2>/dev/null | grep -E 'Jeeves|JetsamEvent' | head -20 || echo '(none)'")
        result = await self.run(host, password, script, timeout=60)
        return {"text": result.stdout}
