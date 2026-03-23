#!/usr/bin/env python3
"""Render config/profiles.local.env from yggclient TOML."""

from __future__ import annotations

import argparse
import pathlib
import tomllib


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", nargs="?", default="yggclient.local.toml")
    parser.add_argument("output", nargs="?", default="config/profiles.local.env")
    args = parser.parse_args()

    config_path = pathlib.Path(args.config)
    output_path = pathlib.Path(args.output)

    data = tomllib.loads(config_path.read_text())
    identity = data.get("identity", {})
    network = data.get("network", {})
    sync = data.get("sync", {})
    services = data.get("services", {})

    lines = [
        "# Generated from yggclient.local.toml",
        f"PROFILE_NAME={shell_quote(str(identity.get('profile_name', 'workstation')))}",
        f"USER_NAME={shell_quote(str(identity.get('user_name', 'pi')))}",
        f"USER_HOME={shell_quote(str(identity.get('user_home', '/home/pi')))}",
        f"SSH_HOST={shell_quote(str(network.get('ssh_host', 'example-host')))}",
        f"SSH_USER={shell_quote(str(network.get('ssh_user', identity.get('user_name', 'pi'))))}",
        f"APT_HTTP_PROXY={shell_quote(str(network.get('apt_http_proxy', '')))}",
        f"APT_HTTPS_PROXY={shell_quote(str(network.get('apt_https_proxy', '')))}",
        f"YGGSYNC_REPO={shell_quote(str(sync.get('yggsync_repo', 'https://github.com/yggdrasilhq/yggsync')))}",
        f"YGGSYNC_CONFIG={shell_quote(str(sync.get('yggsync_config', '~/.config/ygg_sync.toml')))}",
        f"SAMBA_HOST={shell_quote(str(sync.get('samba_host', 'nas.lan')))}",
        f"SAMBA_SHARE={shell_quote(str(sync.get('samba_share', 'data')))}",
        f"SAMBA_USER={shell_quote(str(sync.get('samba_user', '')))}",
        f"SAMBA_USERNAME={shell_quote(str(sync.get('samba_username', sync.get('samba_user', ''))))}",
        f"SAMBA_PASSWORD_ENV={shell_quote(str(sync.get('samba_password_env', 'SAMBA_PASSWORD')))}",
        f"SCREENCASTS_REMOTE={shell_quote(str(sync.get('screencasts_remote', '')))}",
        f"ENABLE_YGGSYNC={shell_quote('1' if sync.get('enable_yggsync', True) else '0')}",
        f"INSTALL_DESKTOP_TIMER={shell_quote('1' if services.get('install_desktop_timer', True) else '0')}",
        f"INSTALL_SHIFT_SYNC={shell_quote('1' if services.get('install_shift_sync', False) else '0')}",
        f"INSTALL_KMONAD={shell_quote('1' if services.get('install_kmonad', False) else '0')}",
        "",
    ]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
