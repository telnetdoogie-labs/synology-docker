# synology-docker

> [!NOTE]
> An unofficial but battle‑tested way to update Docker Engine & Docker Compose on Synology NAS.
>
> Originally forked from [markdumay/synology-docker](https://github.com/markdumay/synology-docker)

[![CI](https://github.com/telnetdoogie-labs/synology-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/telnetdoogie-labs/synology-docker/actions/workflows/ci.yml) ![Last Commit][synology-docker-last-commit] ![Issues][synology-docker-issues] ![Pull Requests][synology-docker-pulls] ![License][synology-docker-license]

## Why this exists

Synology ships Docker or, as they call it in later versions "Container Manager"... but it's OLD. Really old.

This repo gives you a **repeatable, reversible, and reasonably safe** way to:

- Update Docker Engine on Synology to the latest
- Update Docker Compose
- Escape Synology’s legacy `db` log driver
- Roll back if something goes sideways

If you’re comfortable with SSH and `sudo`, this is for you.

> [!IMPORTANT]\
> **This is not supported by Synology.**
> You can absolutely break things if you ignore instructions. Always have backups.
> Once upgraded, The ContainerManager UI will no longer work reliably for managing containers or observing logs.

### DSM Version

Before using this, update to the most recent version of DSM that you can. That'll avoid many issues and will make sure the minor version of your kernel is up to date. I can't keep track of all of the older minor kernel versions for each platform, that would become unmanageable. Sometimes you'll need to download the latest DSM patch manually as it may not show as an automatic update for your model. Look for your latest DSM [here](https://www.synology.com/en-br/support/download)

### Nvidia users

If you use the Nvidia runtime, you may need to re‑run:

```bash
nvidia-ctk runtime configure
```

or restart the Nvidia driver **after** running this script.

### Portainer users (seriously, read this)

Portainer currently **persists the original logging driver** used when a container was created. This means:

- Containers created with the `db` logger will _stay broken_ after upgrade
- You **must recreate** them to switch to `local`

> [!TIP]
> 👉 **Fix your loggers before upgrading Docker** or you’ll spend hours recreating containers anyway.

## What this script actually does

At a high level:

1. Downloads official Docker & Compose binaries
2. Backs up your existing Docker install
3. Stops Docker safely
4. Replaces binaries & config
5. For Docker 28+, installs the `iptable_raw` / `ip6table_raw` kernel modules and loads them before Docker starts (a systemd drop-in on DSM 7, so it survives Container Manager updates). If you're already on the latest Docker, `sudo ./syno_docker_update.sh only_script` moves an older setup over to the drop-in
6. Restarts Docker

Everything is scripted. Nothing is magic. Rollbacks are built‑in.

## Installation

SSH into your NAS and clone the repo:

```bash
git clone https://github.com/telnetdoogie-labs/synology-docker
cd synology-docker
```

## 🚀 First‑time upgrade (do this once, carefully)

> [!NOTE]
> **TL;DR:** Fix logging → recreate containers → upgrade Docker

### Step 1: Switch Docker’s default log driver

```bash
sudo ./syno_docker_update.sh logger
```

This:

- Sets Docker’s default log driver to `local`
- Restarts Docker

The updater now refuses to install a new Docker engine while any container still uses the removed `db` logger. Fix those containers first: recreate them from their Compose project, or use a migration tool such as [stateful-docker-migration-flow](https://github.com/gundestrup/stateful-docker-migration-flow) to export non‑Compose containers to reviewed Compose projects before recreating them.

Then check which containers are _still_ using `db`:

```bash
./syno_docker_list_containers.sh
```

Example output:

```
Container            Compose_Location                               Logger
-------------------  ---------------------------------------------- -------
/transmission        /volume1/docker/downloader/docker-compose.yml  db
/jellyfin            /volume1/docker/jellyfin/docker-compose.yml    db
/dozzle              /volume1/docker/dozzle/docker-compose.yml      local
```

### Step 2: Recreate containers still using `db`

For **each** compose‑managed container using `db`:

```bash
cd /volume1/docker/jellyfin
docker-compose up -d --force-recreate
```

For a **non‑Compose** container, `syno_docker_list_containers.sh` prints a best‑guess `docker run` command you can adapt manually. For a safer path, the companion tool [stateful-docker-migration-flow](https://github.com/gundestrup/stateful-docker-migration-flow) generates a reviewed Compose project per container (private `.env`, manifest tracking, typed `RECREATE` confirmation) so a non‑Compose container can be brought under Compose management:

```bash
# On the NAS, with the migration tool checked out:
./sdmf            # guided menu: inventory -> export -> validate -> recreate
```

Re‑run `syno_docker_list_containers.sh` until **everything** says `local`. The listing includes stopped containers so `db`-logger failures remain visible.

> Containers created via `docker run` will show a _best‑guess_ recreate command. Its environment values are deliberately hidden; replace the required `--env-file /REVIEW_AND_CREATE_ENV_FILE_BEFORE_RUNNING` with a reviewed, private environment file before use. Verify all remaining settings before running it.

### Step 3: Upgrade Docker & Compose

```bash
sudo ./syno_docker_update.sh update
```

If you did the logger step correctly, containers should come back automatically.

## 🔁 Future updates (easy mode)

Once you’ve crossed the logging hurdle, updates are simple:

```bash
cd synology-docker
git pull
sudo ./syno_docker_update.sh update
```

### Lots of containers?

The update has to stop Container Manager, and Synology's stop can give up early if a container is slow to shut down (one container ignoring SIGTERM is enough). If you run a lot of containers, stop them yourself before updating; the script's stop step then has little left to do and finishes in seconds.

If the stop does time out, the script stops before replacing anything and shows the package status. Wait for the stop to finish (or stop the stuck container), check `sudo synopkg status ContainerManager`, then run the update again.

### Docker won't start after an update?

`restore` works even when Container Manager is stopped or won't start, so you can roll back without reinstalling the package:

```bash
sudo ./syno_docker_update.sh restore --backup docker_backup_YYYYMMDD_HHMMSS.tgz
```

## Usage

```bash
sudo ./syno_docker_update.sh [OPTIONS] COMMAND
```

### Commands

| Command         | Description                                                  |
| --------------- | ------------------------------------------------------------ |
| `backup`        | Backup Docker binaries & config                              |
| `download PATH` | Download Docker & Compose binaries                           |
| `install PATH`  | Install from downloaded files                                |
| `restore`       | Restore from backup (works with Container Manager stopped)   |
| `logger`        | Update logging driver only                                   |
| `update`        | Full backup + update                                         |
| `start`         | Start Container Manager, reporting why if it doesn't come up |
| `stop`          | Stop Container Manager, waiting for it to finish             |

## Options

| Option              | Description                                                                  |
| ------------------- | ---------------------------------------------------------------------------- |
| `--docker VERSION`  | Target Docker version                                                        |
| `--compose VERSION` | Target Compose version                                                       |
| `--backup NAME`     | Backup file name                                                             |
| `--force`           | Skip confirmation and compatibility checks; allow an explicitly requested downgrade |
| `--stage`           | Download and extract without installing; print the retained staging path   |
| `--skip-iptables`   | Don't check for / install iptables modules                                   |
| `--fuse-overlayfs`  | Switch storage to fuse-overlayfs (see below)                                |

## fuse-overlayfs (volumes on `aufs` without overlay support)

Most Synology setups use the `btrfs` storage driver and don't need this. It's for one case: Docker on the `aufs` storage driver (typically an ext4 volume) on a kernel without the `overlay` module, such as some models on kernel 4.4.x. Docker 24+ removed `aufs`, so there's no usable storage driver; the update script stops and tells you if you're in this situation.

[fuse-overlayfs](https://github.com/containers/fuse-overlayfs) runs as a containerd proxy snapshotter over FUSE, which these kernels do support. It's opt-in:

```bash
sudo ./syno_docker_update.sh --fuse-overlayfs update
```

or on its own, followed by a restart of Container Manager (or a reboot):

```bash
sudo ./install_fuse_overlayfs.sh
```

Things to know before switching:

- Images and containers from the old storage driver won't be visible afterwards. Pull images and recreate containers; volumes and bind mounts are kept.
- It starts a separate containerd at boot (`/usr/local/etc/rc.d/containerd-fuse-overlayfs.sh`) and disables Synology's `updater` tool, which would otherwise switch the driver back to `aufs`.
- The installer refuses to run on any driver other than `aufs`, and does nothing if your kernel supports overlay.
- To undo it: `sudo ./install_fuse_overlayfs.sh --uninstall`, then restart Container Manager.

## Testing

Run the mocked regression tests in a disposable Docker container:

```bash
docker build -t synology-docker-tests -f tests/Dockerfile .
docker run --rm -v "$PWD:/workspace:ro" synology-docker-tests
```

The supported test scope is DSM major versions 6 and 7 only. These disposable tests cover version selection, stage/backup/restore failure paths, DSM 6/7 service failures, forwarding edits, verified module downloads, AppArmor rollback, and safe container-command rendering. They mock DSM; they do not modify a live Docker service or substitute for kernel and package tests on a NAS.

### Validation status

- **DSM 7:** an earlier hardening revision was live-tested on DSM 7.4.1 with Docker Engine 29.8.2 and Docker Compose 5.6.0, including kernel-module/AppArmor preparation and `db`-logger recovery workflows. This upstream-aligned revision has not yet been retested on a NAS.
- **DSM 6:** implemented and covered by mocked service-control tests, but **not yet validated on physical hardware**. Treat DSM 6 support as best-effort until a real DSM 6 NAS passes the runtime probe, update, workload, and rollback checks.

Before running the updater on a NAS, check its runtime prerequisites with:

```bash
sh tests/check-dsm-runtime.sh 29
```

Replace `29` with the planned Docker Engine major version. The updater requires `/bin/bash`, `jq`, `curl`, `docker`, `realpath`, `readlink -f`, `mktemp -d`, `diff`, `date`, and GNU-compatible `timeout --foreground`, in addition to standard shell utilities. It also needs DSM's `synopkg` (DSM 7) or `synoservicectl` (DSM 6). For a Docker Engine 28+ target, the probe additionally checks `insmod`, `lsmod`, `iptables`, and `/bin/get_key_value`. Kernel modules are downloaded over HTTPS (TLS 1.2) from the matching `synology-kernelmodules` release for your kernel and platform; unsupported combinations need manually installed modules. `/bin/sh` may be a different shell; run scripts through their shebangs rather than invoking Bash scripts with `sh`. Semgrep and SonarQube are review tools for a development host or CI, not runtime dependencies on the NAS.

The [virtual-dsm project](https://github.com/vdsm/virtual-dsm) can boot selected DSM 7 `.pat` releases, but requires a Linux KVM host; its README says Docker Desktop on macOS is unsupported. Its DSM 6 path has an [open D-Bus stability issue](https://github.com/vdsm/virtual-dsm/issues/1122), so validate DSM 6 on real hardware. The project further restricts use of Virtual DSM to official Synology hardware. Use actual NAS hardware for package, service-control, and kernel-module integration testing; keep every test to DSM 6 or DSM 7.

### Manual integration matrix

Run these checks only in a disposable, snapshot-backed environment with the Synology Docker package already installed:

| DSM major | Suggested coverage | Environment |
| ---------- | ------------------ | ----------- |
| 6 | Latest DSM 6.2.4 update | Real Synology hardware |
| 7 | DSM 7.1 and 7.2 | Real hardware or supported Virtual DSM/KVM host |

For each environment, run `sh tests/check-dsm-runtime.sh 29` (using the planned Engine major), record `docker -v` and `docker-compose -v`, start a small representative workload, then run `sudo ./syno_docker_update.sh update`. Verify the service is started, both version commands succeed, and the workload is healthy. Test rollback separately with a named backup and verify the restored versions. Do not treat a successful Virtual DSM run as coverage of physical kernel-module or driver compatibility.

An update stops rather than silently downgrading if release detection fails or an automatic target is older than the installed version. To deliberately downgrade during `update`, specify `--docker VERSION` or `--compose VERSION` together with `--force`; an older offline Docker archive passed to `install PATH` also requires `--force`. Required module and AppArmor preparation is still performed. Backups are private and are never overwritten. `--stage update` leaves downloads in the printed private directory so they can be inspected or passed to `install PATH`. If a change fails after the service has stopped, the script reports the backup path and exits nonzero; it does not automatically restart mixed binaries. Diagnose the failure and restore the backup with `sudo ./syno_docker_update.sh --backup /path/to/backup.tgz restore` before retrying.

## Contributing

PRs are **VERY** welcome here. Many of the recent updates have been contributed by users just like you.

1. Open an [Issue](https://github.com/telnetdoogie-labs/synology-docker/issues)
2. [Fork the repo](https://github.com/telnetdoogie-labs/synology-docker/fork)
3. Make and test your change on real hardware
4. Submit a PR back to this repo, and link with a comment to the Issue you created.
5. Provide details on what you did, what you've tested it on, and the results of those tests.

## Credits

- Original work by [@markdumay](https://github.com/markdumay)
- Extensive testing by [@mrmuiz](https://github.com/mrmuiz)
- Kernel 5.x runc issue / resolution and additional repo contributions and maintenance by [@bslatyer](https://github.com/bslatyer)
- Network‑pain endurance by [@CodeNodeNomad](https://github.com/CodeNodeNomad)
- Awesome IP Forward rules fix and AppArmor update for v29+ by [@Salvora](https://github.com/Salvora)
- AppArmor update / fix by [@Auddis](https://github.com/Auddis)
- fuse-overlayfs support by [@doctorpangloss](https://github.com/doctorpangloss) ([AppMana](https://github.com/AppMana/forks-synology-docker))

## Special Thanks

- [@bslatyer](https://github.com/bslatyer) for repo maintenance and proactive stewardship and co-ownership
- **Marius** @ [MariusHosting](https://mariushosting.com) for linking to the repo from his [August 2026 post](https://mariushosting.com/synology-new-docker-version-24-0-2-1706/)

## Origin

Forked from [https://github.com/markdumay/synology-docker](https://github.com/markdumay/synology-docker)

[synology-docker-last-commit]: https://img.shields.io/github/last-commit/telnetdoogie/synology-docker.svg
[synology-docker-issues]: https://img.shields.io/github/issues/telnetdoogie/synology-docker.svg
[synology-docker-pulls]: https://img.shields.io/github/issues-pr-raw/telnetdoogie/synology-docker.svg
[synology-docker-license]: https://img.shields.io/github/license/telnetdoogie/synology-docker.svg
