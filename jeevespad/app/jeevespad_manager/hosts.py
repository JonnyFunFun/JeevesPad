"""Validation of wallPad addresses.

Addresses end up as `ssh`/`scp` arguments (root@<host>), so anything that isn't plainly an
IP address or a host name is refused: a value starting with "-" would be read as an ssh
option (such as -oProxyCommand=..., which runs a command).
"""

from __future__ import annotations

import ipaddress
import re

_LABEL = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


class InvalidHost(ValueError):
    pass


def normalize_host(value: str) -> str:
    """The address, cleaned up, or InvalidHost."""
    host = (value or "").strip()
    if host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    if not host:
        raise InvalidHost("Enter the iPad's IP address or host name")
    try:
        return str(ipaddress.ip_address(host))
    except ValueError:
        pass
    name = host[:-1] if host.endswith(".") else host
    if len(name) > 253 or not all(_LABEL.match(label) for label in name.split(".")):
        raise InvalidHost(f"{value!r} isn't a valid IP address or host name")
    return name


def is_ipv6(host: str) -> bool:
    try:
        return ipaddress.ip_address(host).version == 6
    except ValueError:
        return False
