"""The Jeeves app package (Jeeves.ipa) installed on wallPads.

The app can't build Jeeves (that needs Theos and the iOS 9.3 SDK), so it installs a
package from one of two slots:
- custom: one the user uploaded (for example their own build from build_ipa.sh). While
  it's there, it's the one installed.
- published: downloaded from a URL, by default the latest GitHub release.
Removing the custom package goes back to the published one.
"""

from __future__ import annotations

import json
import os
import plistlib
import shutil
import time
import zipfile

import aiohttp

DEFAULT_URL = "https://github.com/JonnyFunFun/JeevesPad/releases/latest/download/Jeeves.ipa"
MAX_SIZE = 200 * 1024 * 1024
MAX_UNPACKED = 1024 * 1024 * 1024  # Jeeves.app is a few MB; refuse "zip bombs"
MAX_FILES = 20000
APP_DIR_NAME = "Jeeves.app"


class PackageError(Exception):
    pass


class Package:
    """One package slot: Jeeves.ipa, its details, and the extracted Jeeves.app."""

    def __init__(self, directory: str) -> None:
        os.makedirs(directory, exist_ok=True)
        self.ipa_path = os.path.join(directory, "Jeeves.ipa")
        self.meta_path = os.path.join(directory, "Jeeves.ipa.json")
        self.extract_dir = os.path.join(directory, "payload")

    @property
    def app_dir(self) -> str:
        return os.path.join(self.extract_dir, "Payload", APP_DIR_NAME)

    def info(self) -> dict | None:
        if not os.path.exists(self.ipa_path):
            return None
        try:
            with open(self.meta_path) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def install_ready(self) -> str:
        """Path of the extracted Jeeves.app, extracting it if needed."""
        if not os.path.exists(self.ipa_path):
            raise PackageError("There's no Jeeves app package yet. Upload Jeeves.ipa or download it on the App page.")
        if not os.path.isdir(self.app_dir):
            self._extract()
        return self.app_dir

    def _extract(self) -> dict:
        shutil.rmtree(self.extract_dir, ignore_errors=True)
        os.makedirs(self.extract_dir)
        root = os.path.realpath(self.extract_dir)
        with zipfile.ZipFile(self.ipa_path) as archive:
            members = archive.infolist()
            if len(members) > MAX_FILES or sum(m.file_size for m in members) > MAX_UNPACKED:
                raise PackageError("That package is far too large to be Jeeves")
            for member in members:
                target = os.path.realpath(os.path.join(root, member.filename))
                if not target.startswith(root + os.sep):
                    raise PackageError(f"The package contains an unsafe path: {member.filename}")
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise PackageError(f"The package contains a symbolic link: {member.filename}")
            archive.extractall(root)
        info_plist = os.path.join(self.app_dir, "Info.plist")
        if not os.path.exists(info_plist):
            raise PackageError("That isn't a Jeeves package (no Payload/Jeeves.app/Info.plist)")
        with open(info_plist, "rb") as f:
            info = plistlib.load(f)
        if info.get("CFBundleIdentifier") != "com.jeeves.Jeeves":
            raise PackageError(f"That package is {info.get('CFBundleIdentifier')!r}, not Jeeves")
        return info

    def remove(self) -> None:
        for path in (self.ipa_path, self.meta_path):
            if os.path.exists(path):
                os.remove(path)
        shutil.rmtree(self.extract_dir, ignore_errors=True)

    def store(self, data: bytes, source: str) -> dict:
        """Saves and validates a new package."""
        if not data.startswith(b"PK"):
            raise PackageError("That isn't an .ipa file (a zip archive)")
        tmp = self.ipa_path + ".new"
        with open(tmp, "wb") as f:
            f.write(data)
        old = self.ipa_path + ".old"
        if os.path.exists(self.ipa_path):
            os.replace(self.ipa_path, old)
        os.replace(tmp, self.ipa_path)
        try:
            info = self._extract()
        except (PackageError, zipfile.BadZipFile, plistlib.InvalidFileException) as err:
            # Put the previous package back
            if os.path.exists(old):
                os.replace(old, self.ipa_path)
                self._extract()
            else:
                os.remove(self.ipa_path)
                shutil.rmtree(self.extract_dir, ignore_errors=True)
            raise PackageError(str(err) if isinstance(err, PackageError) else "The package couldn't be read") from err
        if os.path.exists(old):
            os.remove(old)
        meta = {
            "version": info.get("CFBundleShortVersionString", "?"),
            "build": info.get("CFBundleVersion", "?"),
            "size": len(data),
            "source": source,
            "added": time.time(),
        }
        with open(self.meta_path, "w") as f:
            json.dump(meta, f)
        return meta

    async def download(self, url: str) -> dict:
        if not url.lower().startswith(("https://", "http://")):
            raise PackageError("The package address must start with https:// or http://")
        timeout = aiohttp.ClientTimeout(total=300)
        try:
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(url) as response:
                    if response.status != 200:
                        raise PackageError(f"Download failed: HTTP {response.status} from {url}")
                    data = bytearray()
                    async for chunk in response.content.iter_chunked(65536):
                        data.extend(chunk)
                        if len(data) > MAX_SIZE:
                            raise PackageError("The download is too large to be a Jeeves package")
        except aiohttp.ClientError as err:
            raise PackageError(f"Download failed: {err}") from err
        return self.store(bytes(data), url)


class PackageStore:
    """The custom (uploaded) and published (downloaded) packages; custom wins."""

    CUSTOM = "custom"
    PUBLISHED = "published"

    def __init__(self, data_dir: str) -> None:
        root = os.path.join(data_dir, "packages")
        self.custom = Package(os.path.join(root, self.CUSTOM))
        self.published = Package(os.path.join(root, self.PUBLISHED))
        self._migrate(data_dir)

    def _migrate(self, data_dir: str) -> None:
        """Earlier versions kept a single package in the data folder."""
        old_ipa = os.path.join(data_dir, "Jeeves.ipa")
        if not os.path.exists(old_ipa):
            return
        old_meta = old_ipa + ".json"
        try:
            with open(old_meta) as f:
                source = json.load(f).get("source", "")
        except (OSError, ValueError):
            source = ""
        slot = self.published if source.startswith(("http://", "https://")) else self.custom
        if not os.path.exists(slot.ipa_path):
            os.replace(old_ipa, slot.ipa_path)
            if os.path.exists(old_meta):
                os.replace(old_meta, slot.meta_path)
        for leftover in (old_ipa, old_meta):
            if os.path.exists(leftover):
                os.remove(leftover)
        shutil.rmtree(os.path.join(data_dir, "payload"), ignore_errors=True)

    def active_slot(self) -> str | None:
        if self.custom.info():
            return self.CUSTOM
        if self.published.info():
            return self.PUBLISHED
        return None

    def active(self) -> Package | None:
        slot = self.active_slot()
        return {self.CUSTOM: self.custom, self.PUBLISHED: self.published}.get(slot) if slot else None

    def info(self) -> dict:
        return {"active": self.active_slot(), self.CUSTOM: self.custom.info(), self.PUBLISHED: self.published.info()}

    def describe_active(self) -> str:
        package = self.active()
        if package is None:
            return "no package"
        meta = package.info() or {}
        owner = "your uploaded package" if package is self.custom else "the published release"
        return f"{owner}, Jeeves {meta.get('version', '?')} ({meta.get('build', '?')})"

    def install_ready(self) -> str:
        package = self.active()
        if package is None:
            raise PackageError("There's no Jeeves app package yet. Upload Jeeves.ipa or download it on the App package tab.")
        return package.install_ready()

    def upload(self, data: bytes, filename: str) -> dict:
        return self.custom.store(data, filename or "upload")

    def remove_custom(self) -> None:
        self.custom.remove()

    async def download(self, url: str) -> dict:
        return await self.published.download(url)
