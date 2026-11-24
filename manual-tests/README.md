# Manual tests

These tests can be run manually for sanity checks and / or before- and after- an update to check for continued valuable functionality. Any tests here should clean up after themselves even on failure and output clearly passes or failures.

Unlike the mocked suite in `tests/`, these run against the live Docker daemon on your NAS. They are not run in CI.

## Docker networking

```bash
sudo ./manual-tests/test_docker_network.sh
```

The script prints the kernel, DSM, and Docker Engine versions, `net.ipv4.ip_forward`, and the current `FORWARD` / `DEFAULT_FORWARD` rules. It then creates a few temporary networks and containers (all named `syno-net-check-<pid>-*`), waits 20 seconds for Docker and DSM network events to settle, and checks:

| Check                                                                                 | What a failure means                                                                                                                                                            |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Internal network is isolated from the default bridge (immediately and after settling) | A container on the default bridge can reach a container on an `--internal` network.                                                                                             |
| Containers on separate bridges cannot reach each other                                | Docker's isolation rules between user-defined networks are missing.                                                                                                             |
| Host namespace reaches a published container port                                     | Port publishing (`-p`) is not working.                                                                                                                                          |
| Unpublished container has no host-port mapping                                        | A container started without `-p` got a published port.                                                                                                                          |
| Containers on the same bridge reach each other                                        | Container-to-container traffic or Docker's DNS on a user-defined network is broken.                                                                                             |
| Bridge container reaches `EGRESS_URL`                                                 | Containers can't get out to the network. This usually means Docker's `FORWARD` jumps are missing (see [#134](https://github.com/telnetdoogie-labs/synology-docker/issues/134)). |

On a working setup, every check passes, both before and after an update. If a check fails, include the full output when you open an issue.

The script pulls `nginx:alpine` and `busybox:1.36` if they aren't already present, and removes everything it created when it exits, even after a failure or Ctrl+C. Pulled images are kept. If the script is killed outright, remove anything left over with:

```bash
sudo docker rm -f $(sudo docker ps -aq --filter name=syno-net-check-)
sudo docker network rm $(sudo docker network ls -q --filter name=syno-net-check-)
```

The outbound check fetches `http://example.com/` by default. To use a different URL, or to skip the check on a NAS without internet access:

```bash
sudo EGRESS_URL=http://192.168.1.1/ ./manual-tests/test_docker_network.sh
sudo EGRESS_URL= ./manual-tests/test_docker_network.sh
```

Exit status: `0` all checks passed, `1` at least one check failed, `2` the test could not be set up (for example, Docker isn't running or the images couldn't be pulled).
