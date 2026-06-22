# synology-docker

> [!NOTE]
> An unofficial but battle‑tested way to update Docker Engine & Docker Compose on Synology NAS.
>
> Originally forked from [markdumay/synology-docker](https://github.com/markdumay/synology-docker)

![Last Commit][synology-docker-last-commit] ![Issues][synology-docker-issues] ![Pull Requests][synology-docker-pulls] ![License][synology-docker-license]

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

> [!WARNING]\
> **Some users are experiencing Container Manager failures after updating to Docker 29.x.**
>
> > This is a known issue between Synology's Container Manager and the upstream Docker 29.x release. If you run into this, roll back using:
> >
> > ```bash
> > sudo ./syno_docker_update.sh restore --backup [backup_name]
> > ```
> >
> > Until Synology or upstream Docker resolves the compatibility issue, it is recommended to pin to the latest stable 28.x release using `--docker 28.x.x`.

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
git clone https://github.com/telnetdoogie/synology-docker
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

Re‑run `syno_docker_list_containers.sh` until **everything** says `local`.

> Containers created via `docker run` will show a _best‑guess_ recreate command. Verify it before running.

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
| `--force`           | Skip compatibility checks |
| `--stage`           | Download only, no install |

## Contributing

PRs welcome.

1. Fork
2. Test on real hardware
3. Explain _why_ the change exists

## Credits

- Original work by [@markdumay](https://github.com/markdumay)
- Extensive testing by [@mrmuiz](https://github.com/mrmuiz)
- Network‑pain endurance by [@CodeNodeNomad](https://github.com/CodeNodeNomad)
- Kernel 5.x runc issue / resolution and additional repo contributions by [@bslatyer](https://github.com/bslatyer)

## Origin

Forked from [https://github.com/markdumay/synology-docker](https://github.com/markdumay/synology-docker)

[synology-docker-last-commit]: https://img.shields.io/github/last-commit/telnetdoogie/synology-docker.svg
[synology-docker-issues]: https://img.shields.io/github/issues/telnetdoogie/synology-docker.svg
[synology-docker-pulls]: https://img.shields.io/github/issues-pr-raw/telnetdoogie/synology-docker.svg
[synology-docker-license]: https://img.shields.io/github/license/telnetdoogie/synology-docker.svg
