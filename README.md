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
5. Restarts Docker

Everything is scripted. Nothing is magic. Rollbacks are built‑in.

## Installation

SSH into your NAS and clone the repo:

```bash
git clone https://github.com/telnetdoogie-labs/synology-docker
cd synology-docker
```

## Guided recovery and update menu

The easiest entry point is:

```bash
./syno_docker_recovery.sh
```

The menu starts with three workflows and shows the recommended order under each:

1. **Upgrade Docker/Compose** — runtime check, inventory, backup, update, verification.
2. **Downgrade or restore Docker/Compose** — runtime check, backup, restore/downgrade, verification.
3. **Convert containers** — inventory, export, validation, recreation, manifest/status verification.

Each workflow opens a submenu with only its relevant checks and actions. The menu does not delete a container, run an update, downgrade, or restore a backup without typed confirmation. Environment values remain in private `.env` files and are not shown.

The same actions can be run non-interactively, for example:

```bash
./syno_docker_recovery.sh preflight 29
./syno_docker_recovery.sh list
./syno_docker_recovery.sh next /volume1/docker/recover
./syno_docker_recovery.sh validate /volume1/docker/recover crashplan
./syno_docker_recovery.sh manifest /volume1/docker/recover
```

`recreate`, `update`, and `restore` are deliberately available but require confirmation because they remove a container record, replace Docker binaries, or roll back configuration.

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

For a non‑Compose container, generate a reviewed Compose file directly from `docker inspect`:

```bash
./syno_docker_list_containers.sh --compose-dir /volume1/docker/container-name container-name
cd /volume1/docker/container-name
sudo docker rm container-name
sudo docker compose -f container-name.docker-compose.yml up -d --force-recreate
```

For a guided one-container-at-a-time recovery, use the container-data root and `--container-dirs --next`:

```bash
./syno_docker_list_containers.sh \
  --compose-dir /volume1/docker \
  --container-dirs \
  --next
```

This selects the first container still using `db` and writes its files under `/volume1/docker/<name>/`. After reviewing the files, removing the old stopped container, and successfully recreating it, run the same command again to process the next `db` container. If the next pending container is already Compose-managed, the script prints its `docker compose up -d --force-recreate` command instead of generating another file.

To convert every non‑Compose container into separate directories, omit `--next`:

```bash
./syno_docker_list_containers.sh \
  --compose-dir /volume1/docker/recreated-containers \
  --container-dirs
```

The script maintains a private JSON state file at `<compose-dir>/compose-export-manifest.json` (or the path supplied with `--manifest`). It records image names, logger values, output paths, and statuses such as `written`, `already-converted`, `candidate-generated`, `compose-managed`, and `updated`; it does not record environment values.

The converter writes a private `<name>.env` file containing environment values and a `<name>.docker-compose.yml` file that forces the `local` logger. Anonymous Docker volumes with generated 64-character names are preserved as `external` volumes by default so no data is silently discarded. If review shows a volume such as `HASH:/storage:rw` is disposable, add `--fresh-anonymous-volumes`; the generated service then uses the anonymous mount `/storage:rw`, and the hash is omitted from the top-level `volumes:` block so Docker creates a fresh volume. Do not use that option when the anonymous volume might contain required data.

On a repeat run, identical output is reported as `Already converted`. If an existing Compose file differs, it is not overwritten: the YAML diff is shown and the new candidate is saved as `<name>.docker-compose.yml.generated`; differing environment data is reported without printing values and saved as `<name>.env.generated`. Use `--force` only after reviewing those differences to replace the existing files. It also accepts a Synology Container Manager JSON export through `syno_container_export_to_compose.sh`; when using that format, pass `--volume-root /volumeN` if the NAS data is not under `/volume1`. Review mounts and ports before running. Removing the old stopped container does not remove its bind-mounted folders or named volumes.

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

## Usage

```bash
sudo ./syno_docker_update.sh [OPTIONS] COMMAND
```

### Commands

| Command         | Description                        |
| --------------- | ---------------------------------- |
| `backup`        | Backup Docker binaries & config    |
| `download PATH` | Download Docker & Compose binaries |
| `install PATH`  | Install from downloaded files      |
| `restore`       | Restore from backup                |
| `logger`        | Update logging driver only         |
| `update`        | Full backup + update               |

## Options

| Option              | Description               |
| ------------------- | ------------------------- |
| `--docker VERSION`  | Target Docker version     |
| `--compose VERSION` | Target Compose version    |
| `--backup NAME`     | Backup file name          |
| `--force`           | Skip confirmation and compatibility checks; allow an explicitly requested downgrade |
| `--stage`           | Download and extract without installing; print the retained staging path |

## Testing

Run the mocked regression tests in a disposable Docker container:

```bash
docker build -t synology-docker-tests -f tests/Dockerfile .
docker run --rm -v "$PWD:/workspace:ro" synology-docker-tests
```

The supported test scope is DSM major versions 6 and 7 only. These disposable tests cover version selection, stage/backup/restore failure paths, DSM 6/7 service failures, forwarding edits, verified module downloads, AppArmor rollback, and safe container-command rendering. They mock DSM; they do not modify a live Docker service or substitute for kernel and package tests on a NAS.

### Validation status

- **DSM 7:** live-tested on DSM 7.4.1 with Docker Engine 29.8.2 and Docker Compose 5.6.0, including kernel-module/AppArmor preparation and `db`-logger recovery workflows.
- **DSM 6:** implemented and covered by mocked service-control tests, but **not yet validated on physical hardware**. Treat DSM 6 support as best-effort until a real DSM 6 NAS passes the runtime probe, update, workload, and rollback checks.

Before running the updater on a NAS, check its runtime prerequisites with:

```bash
sh tests/check-dsm-runtime.sh 29
```

Replace `29` with the planned Docker Engine major version. The updater requires `/bin/bash`, `jq`, `curl`, `docker`, `realpath`, `readlink -f`, `mktemp -d`, `diff`, `date`, and GNU-compatible `timeout --foreground`, in addition to standard shell utilities. It also needs DSM's `synopkg` (DSM 7) or `synoservicectl` (DSM 6). For a Docker Engine 28+ target, the probe additionally checks `sha256sum`, `insmod`, `lsmod`, `iptables`, and `/bin/get_key_value`. Automatic module downloads are pinned to an upstream commit and checked against platform-specific SHA-256 hashes; new kernel/platform combinations need reviewed hashes or manually installed modules. `/bin/sh` may be a different shell; run scripts through their shebangs rather than invoking Bash scripts with `sh`. Semgrep and SonarQube are review tools for a development host or CI, not runtime dependencies on the NAS.

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

## Special Thanks

- [@bslatyer](https://github.com/bslatyer) for repo maintenance and proactive stewardship and co-ownership
- **Marius** @ [MariusHosting](https://mariushosting.com) for linking to the repo from his [August 2026 post](https://mariushosting.com/synology-new-docker-version-24-0-2-1706/)

## Origin

Forked from [https://github.com/markdumay/synology-docker](https://github.com/markdumay/synology-docker)

[synology-docker-last-commit]: https://img.shields.io/github/last-commit/telnetdoogie/synology-docker.svg
[synology-docker-issues]: https://img.shields.io/github/issues/telnetdoogie/synology-docker.svg
[synology-docker-pulls]: https://img.shields.io/github/issues-pr-raw/telnetdoogie/synology-docker.svg
[synology-docker-license]: https://img.shields.io/github/license/telnetdoogie/synology-docker.svg
