# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""
Jenkins plugins resolver
"""

import json
import asyncio
import argparse
from typing import Tuple
import hashlib
import aiohttp


def map_pinned_versions(plugins: list[str]) -> dict[str, str | None]:
    """Transforms list of colon separated plugins and versions into a dict"""
    pins = {}
    for plugin in plugins:
        parts = plugin.split(":", 1)
        pins[parts[0]] = parts[1] if len(parts) > 1 else None

    return pins


def nix_hash(hex_bytes: bytes) -> str:
    """Calculates a nix style base32 hash from hex bytes"""
    nix_charset = "0123456789abcdfghijklmnpqrsvwxyz"
    out_len = (len(hex_bytes) * 8 - 1) // 5 + 1

    hash_output = []
    for n in range(out_len - 1, -1, -1):
        b = n * 5
        i = b // 8
        j = b % 8
        v1 = hex_bytes[i] >> j
        v2 = 0 if i >= len(hex_bytes) - 1 else hex_bytes[i + 1] << (8 - j)
        v = v1 | v2
        idx = v % len(nix_charset)
        hash_output.append(nix_charset[idx])

    return "".join(hash_output)


async def fetch_manifest(session: aiohttp.ClientSession, version: str) -> dict:
    """Get plugin manifest from jenkins update center"""
    print(f"Fetching plugin manifest for Jenkins {version}")
    url = f"https://updates.jenkins.io/update-center.actual.json?version={version}"
    print(url)
    async with session.get(url) as response:
        response.raise_for_status()
        data = await response.json()
        return data["plugins"]


async def download_and_hash(
    session: aiohttp.ClientSession, plugin: dict
) -> Tuple[str, str]:
    """Download the .hpi file and calculate its nix hash"""
    async with session.get(plugin["url"]) as response:
        response.raise_for_status()
        b = await response.content.read()
        sha256 = nix_hash(hashlib.sha256(b).digest())
        return plugin["name"], sha256


def construct_plugin(name: str, version: str) -> dict:
    """Create the plugin object"""
    return {
        "name": name,
        "version": version,
        "url": f"https://updates.jenkins.io/download/plugins/{name}/{version}/{name}.hpi",
    }


def resolve_dependencies_recursive(
    plugins: dict, resolved: dict, manifest: dict, plugin: str
) -> dict:
    """Recursively get all plugin's dependencies"""
    if resolved.get(plugin) is not None:
        return resolved

    resolved[plugin] = construct_plugin(
        plugin,
        plugins.get(plugin) or manifest[plugin]["version"],
    )

    for dep in manifest[plugin].get("dependencies", []):
        resolved = resolve_dependencies_recursive(
            plugins, resolved, manifest, dep["name"]
        )

    return resolved


async def main():
    """Main entrypoint"""
    parser = argparse.ArgumentParser(description="Jenkins plugins resolver")
    parser.add_argument(
        "--jenkins-version",
        help="Version of Jenkins to resolve the plugins against",
        required=True,
    )
    parser.add_argument(
        "--plugins-file",
        help="Path to a textfile that lists the target jenkins plugin names",
        required=True,
    )
    parser.add_argument("--output", "-o", help="Json output file")
    args = parser.parse_args()

    plugins = {}
    with open(args.plugins_file, "r", encoding="utf-8") as f:
        plugins = map_pinned_versions(f.read().split())

    async with aiohttp.ClientSession() as session:
        manifest = await fetch_manifest(session, args.jenkins_version)
        resolved = {}
        for name in plugins:
            print(f"Resolving dependencies for plugin '{name}'")
            resolve_dependencies_recursive(plugins, resolved, manifest, name)

        tasks = []
        for plugin in resolved.values():
            tasks.append(download_and_hash(session, plugin))

        print("Downloading and hashing plugin archives...")
        results = await asyncio.gather(*tasks)
        for name, sha256 in results:
            resolved[name]["sha256"] = sha256

        resolved_sorted_list = sorted(list(resolved.values()), key=lambda x: x["name"])
        output = json.dumps(resolved_sorted_list, indent=2)
        if args.output is None:
            print(output)
        else:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(output)
                print(f"Wrote plugin manifest into '{args.output}'")


if __name__ == "__main__":
    asyncio.run(main())
