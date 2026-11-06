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
failed_cases=()
for case_file in "${cases[@]}"; do
  case_name=${case_file##*/}
  printf 'RUN %s\n' "$case_name"
  if bash "$case_file"; then
    printf 'PASS %s\n' "$case_name"
    ((passed+=1))
  else
    printf 'FAIL %s\n' "$case_name" >&2
    failed_cases+=("$case_name")
  fi
done
if ((${#failed_cases[@]})); then
  printf 'FAIL: %s passed, %s failed\n' "$passed" "${#failed_cases[@]}" >&2
  printf 'Failed cases:\n' >&2
  printf '  %s\n' "${failed_cases[@]}" >&2
  exit 1
fi
printf 'PASS: %s independent test case(s)\n' "$passed"
