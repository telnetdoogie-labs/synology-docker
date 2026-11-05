#!/bin/bash
# The updater supports both DSM 6 and 7, including their distinct package tools.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/dsm_runtime_fixture.sh
source "$(dirname "$0")/../lib/dsm_runtime_fixture.sh"

# Arrange: both DSM package tools are present in the disposable image.
prepare_dsm_runtime_fixture
command='restore' # Isolate DSM compatibility from Docker version availability.

for major in 6 7; do
  # Arrange: write the version file read by the updater, then select its tool.
  set_mock_dsm_version "$major" "$major.2"
  dsm_major_version=$major

  # Act: the updater validates the current DSM and its package controller.
  update_output=$(detect_current_versions)
  validate_syno_tools

  # Expect: both supported versions complete the same updater checks.
  expect_contains "$update_output" "Current DSM version: $major.2" "updater detects DSM $major"
done
