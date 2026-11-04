# Changelog

## Unreleased

- Added GitHub Actions CI for the Docker regression suite and ShellCheck.
- Restricted curl downloads and redirects to HTTPS with a TLS 1.2 minimum so update and kernel-module downloads cannot be downgraded by a redirect.
- Documented the disposable test image's root user as intentional because mocked DSM paths require privileged filesystem access.
- Made `--stage` skip iptables kernel-module and AppArmor installation. Staging should prepare and inspect an update without mutating host configuration.
- Stopped update and restore workflows when binary, ownership, permissions, log-driver, or restore-file operations fail; logger configuration now uses a temporary file and reports invalid JSON or replacement failures. Continuing after a partial install could leave Docker in a mixed or unusable state while reporting success.
- Downloaded iptables modules into a private temporary directory and removed only that directory. The installer must not overwrite or delete same-named files in the caller's working directory.
- Preserved Compose paths containing spaces when sorting and checking container records so valid project files are not misclassified.
- Restricted service-control workflows to DSM 6 and 7 and made unsupported versions fail explicitly. The service-control implementation has no verified path for later major versions.
- Added Docker-based mocked regression tests and a read-only DSM runtime capability probe that accepts DSM 6/7 only and checks the version-specific service manager. The mocks catch command-rendering regressions without touching a live Docker service; the probe helps identify DSM-specific missing tools.
- Documented a DSM 6/7 manual integration matrix, keeping DSM 6 on physical hardware because the Virtual DSM DSM 6 path has a known stability issue. DSM 7 is live-tested; DSM 6 remains best-effort pending physical-hardware validation.
- Failed closed when release lookup fails or an automatic target would downgrade Docker; an older offline Docker archive also requires `--force`. Explicit update downgrades need both `--force` and a target version, while force and offline install still prepare required modules and AppArmor.
- Made backups private, verified, and non-overwriting; included managed AppArmor profile state when present and checked archive extraction and individual restore copies so failures cannot be mistaken for successful rollbacks.
- Kept staged downloads in a per-run private directory and stopped deleting offline install inputs. Forwarding edits now fail on missing anchors or write errors without partially editing the live script, and failed service starts always exit nonzero.
- Downloaded kernel modules over HTTPS (TLS 1.2) from `synology-kernelmodules` `main`. The AppArmor wrapper/profile installer now prepares files before replacement, restores its parser and files on failure, refreshes the wrapper and profile on every run, and only removes managed profiles on restore.
- Recreate hints now suggest the `local` log driver the new engine expects, and the container listing includes stopped containers so `db`-logger failures remain visible.
- Extended mocked regression coverage to the `dockerd.json` logger switch and the non-stage update install path.
- Added regression tests for the standalone forwarding/logging helpers, DSM runtime preflight, and update confirmation prompts.
- Blocked Docker engine update and install workflows when containers still use the removed `db` logger, with a `--force` override; runs that do not replace the engine are not blocked. See the README for recovery options including the companion [stateful-docker-migration-flow](https://github.com/gundestrup/stateful-docker-migration-flow) tool.
