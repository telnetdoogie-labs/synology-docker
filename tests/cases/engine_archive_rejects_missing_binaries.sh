#!/bin/bash
# An Engine archive without docker or dockerd is rejected while extracting, before the package is stopped or any
# installed binary is replaced. Run alone with: bash tests/run.sh engine_archive_rejects_missing_binaries
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/update_run_fixture.sh
source "$(dirname "$0")/../lib/update_run_fixture.sh"

init_update_fixture
prepare_installed_files
prepare_update_run_fixture
mock_installed_versions 28.0.0 2.42.0 1.1.0
installed_before=$(installed_file_hashes)

for missing_binary in docker dockerd; do
  # Arrange: the downloaded archive has every expected file except one.
  if [[ "$missing_binary" = docker ]]; then
    make_engine_archive 29.0.0 dockerd containerd runc
  else
    make_engine_archive 29.0.0 docker containerd runc
  fi
  mock_synopkg started
  : > "$curl_log"

  # Act: update the Engine through the real entrypoint.
  update_status=0
  update_output=$(
    main --force --skip-iptables --path "$test_tmp_dir" --backup "no-$missing_binary.tgz" \
      --docker 29.0.0 --target engine update 2>&1
  ) || update_status=$?

  # Expect: extraction rejects the archive while Docker is still running and untouched.
  expect_eq 1 "$update_status" "archive without $missing_binary stops the update"
  expect_contains "$update_output" 'Docker binaries could not be extracted from archive' \
    "archive without $missing_binary is reported as incomplete"
  expect_contains "$(<"$curl_log")" docker-29.0.0.tgz "archive without $missing_binary was downloaded first"
  expect_not_contains "$update_output" 'Stopping Docker service' "archive without $missing_binary does not stop Docker"
  expect_not_contains "$update_output" 'Installing binaries' "archive without $missing_binary installs nothing"
  expect_file_lacks "$synopkg_log" stop "archive without $missing_binary leaves the package running"
  expect_eq "$installed_before" "$(installed_file_hashes)" "archive without $missing_binary leaves installed files unchanged"
  expect_eq '' "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'docker_update.*' -print -quit)" \
    "archive without $missing_binary leaves no temp directory"
  rm -rf "$mock_downloads/docker-29.0.0.tgz" "$test_tmp_dir/engine-29.0.0"
done
