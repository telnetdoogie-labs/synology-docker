#!/usr/bin/env python3
"""Prove selected Docker cases fail when their *production* behavior is mutated.

Run after building the disposable image: python3 tests/check-mutation-sensitivity.py
Mutated script copies live only in a temporary directory. Docker mounts the checkout
and replacement file read-only; neither production sources nor the NAS are changed.
This is a focused smoke check, not a claim of comprehensive mutation coverage.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
IMAGE = "synology-docker-tests"
# case, root production script, original fragment, replacement, expected test failure
MUTATIONS = [
    (
        "updater_rejects_unsupported_dsm", "syno_docker_update.sh",
        "    6 | 7 ) ;;", "    6 | 7 | 8 ) ;;",
        "FAIL: updater accepted unsupported DSM 8",
    ),
    (
        "updater_rejects_aufs_for_new_engine", "syno_docker_update.sh",
        "terminate \"Docker ${target_docker_version} can't use",
        "echo \"Docker ${target_docker_version} can't use",
        "FAIL: updater accepted Docker 29 with aufs without --force",
    ),
    (
        "fuse_overlayfs_rejects_btrfs_driver", "install_fuse_overlayfs.sh",
        "terminate \"Docker uses the '", "echo \"Docker uses the '",
        "FAIL: fuse-overlayfs installer accepted a btrfs driver switch",
    ),
    (
        "apparmor_wrapper_forwards_stdin_profile", "install_apparmor_profile.sh",
        'cat > "$TMP_FILE" || exit 1', 'cat > /dev/null || exit 1',
        "stdin profile content preserved",
    ),
]


def run_case(case: str, replacement: Path | None = None, source: str = "") -> subprocess.CompletedProcess[str]:
    args = ["docker", "run", "--rm", "-v", f"{ROOT}:/workspace:ro"]
    if replacement is not None:
        args += ["-v", f"{replacement}:/workspace/{source}:ro"]
    args += [IMAGE, "bash", "tests/run.sh", case]
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=False)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="synology-test-mutants-", dir=os.environ.get("TMPDIR")) as directory:
        mutations = list(MUTATIONS)
        modules = (ROOT / "install_iptables_modules.sh").read_text()
        lines = [line for line in modules.splitlines(keepends=True) if "ExecStartPre" in line and "IP6MODULE" in line]
        if len(lines) != 1:
            raise RuntimeError("Expected exactly one IPv6 systemd ExecStartPre in module installer")
        mutations.append((
            "kernel_modules_migrate_to_systemd_dropin", "install_iptables_modules.sh",
            lines[0], lines[0].replace("insmod ${MODULES_FOLDER}/${IP6MODULE}", "true"),
            "drop-in loads IPv6 raw module",
        ))

        for index, (case, source, old, new, failure) in enumerate(mutations):
            original = (ROOT / source).read_text()
            if original.count(old) != 1 or old == new:
                raise RuntimeError(f"Mutation target changed or ambiguous: {source}: {case}")
            baseline = run_case(case)
            if baseline.returncode != 0:
                raise RuntimeError(f"Baseline failed for {case}:\n{baseline.stdout}{baseline.stderr}")
            mutant = Path(directory) / f"mutant-{index}-{source}"
            mutant.write_text(original.replace(old, new))
            result = run_case(case, mutant, source)
            output = result.stdout + result.stderr
            if result.returncode == 0 or failure not in output:
                raise RuntimeError(f"Mutation escaped or failed for the wrong reason: {case}:\n{output}")
            print(f"PASS: {case} detects production mutation in {source}")
    print(f"PASS: {len(mutations)} targeted production mutations rejected")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
