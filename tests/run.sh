#!/bin/bash
# Run in the disposable image: bash tests/run.sh [case-name]
# No arguments runs every case; one name runs only that case. Never run on a NAS.
set -euo pipefail
if [[ "${DSM_MOCK_CONTAINER:-}" != 1 || "$(id -u)" -ne 0 || ! -f /etc/synology-docker-test-image ]]; then
  printf 'Run tests only as root inside the disposable Docker test image\n' >&2
  exit 1
fi
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
if [[ "$#" -gt 1 ]]; then
  printf 'Usage: bash tests/run.sh [case-name]\n' >&2
  exit 2
fi
cases=("$repo_dir"/tests/cases/*.sh)
if [[ "$#" -eq 1 ]]; then
  case_file="$repo_dir/tests/cases/$1.sh"
  if [[ ! -f "$case_file" || "$1" == *[!a-z0-9_]* ]]; then
    printf 'Unknown test case: %s\n' "$1" >&2
    exit 2
  fi
  cases=("$case_file")
fi
passed=0
for case_file in "${cases[@]}"; do
  printf 'RUN %s\n' "${case_file##*/}"
  bash "$case_file"
  printf 'PASS %s\n' "${case_file##*/}"
  ((passed+=1))
done
printf 'PASS: %s independent test case(s)\n' "$passed"
