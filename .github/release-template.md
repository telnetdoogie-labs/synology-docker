### Updating

```bash
cd synology-docker
git pull
sudo ./syno_docker_update.sh update
```

New here, or still have containers on the `db` logger? Follow the [README](https://github.com/{{ repo }}/blob/{{ tag }}/README.md) first.

To use exactly this version, run `git checkout {{ tag }}` in your copy (`git checkout main` returns to the latest), or download `synology-docker.tar.gz` below.

{{ changelog }}
