# Garry's Mod x86-64 + Git Egg

Pterodactyl Egg for a Garry's Mod x86-64 dedicated server, maintained by RefoselDev.

## Features

- installs Steam AppID `4020` from the `x86-64` branch;
- runs with `ghcr.io/refoseldev/games:source`;
- optionally deploys server content from a Git repository;
- optionally synchronizes tracked files with the selected remote branch before startup;
- does not download or mount third-party Counter-Strike: Source content.

Leave `GIT_FOLDER` empty to deploy the repository into the server root (`/home/container`). Set it to a relative path such as `garrysmod` to deploy into a subdirectory.

## Installation

Import [`egg-garrys-mod-x64-github.json`](egg-garrys-mod-x64-github.json) from the Pterodactyl admin panel, then create a server from the imported Egg.

The GHCR image must be published before servers can use the Egg. The companion image source is available in [refoseldev/yolks](https://github.com/refoseldev/yolks).

## Private Git repositories

Use a dedicated read-only token. Credentials are supplied to Git only for authentication and are not written into the repository remote URL.
