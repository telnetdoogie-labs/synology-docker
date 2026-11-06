#!/bin/bash
# Shared inspected container for independent recreate-hint behavior cases.
# Source after test_env.sh and container_fixture.sh; Docker remains a fake function.
# Each case gets its own shell and private temporary directory from test_env.sh.
# shellcheck source=tests/lib/test_env.sh
# shellcheck source=tests/lib/container_fixture.sh
# shellcheck disable=SC2034 # Caller cases assert the run_result set by render_recreate_hint.
# shellcheck disable=SC2154 # test_tmp_dir and repo_dir come from test_env.sh in caller cases.

malicious_source="/tmp/source path/\$(touch $test_tmp_dir/should-not-run-mount)"
malicious_cmd="\$(touch $test_tmp_dir/should-not-run-cmd)"
malicious_env="RECREATE_TEST_APP=one value \$(touch $test_tmp_dir/should-not-run-env)"
DOCKER_FIXTURE=$(jq -cn \
  --arg bind_source "$malicious_source" \
  --arg command_arg "$malicious_cmd" \
  --arg env_value "$malicious_env" '
  [{
    Name: "/review-test",
    Config: {
      Image: "example/test:1",
      Env: [$env_value, "RECREATE_TEST_APP_EXTRA=two"],
      Entrypoint: ["/entry", "--entry-flag"],
      Cmd: ["argument with spaces", "second-argument", $command_arg],
      Tty: true, OpenStdin: false
    },
    HostConfig: {
      PortBindings: {
        "80/tcp": [{HostIp: "127.0.0.1", HostPort: "8080"}, {HostIp: "", HostPort: ""}, {HostIp: "", HostPort: null}],
        "443/tcp": [{HostIp: "", HostPort: "8443"}],
        "53/udp": [{HostIp: "::1", HostPort: "5353"}]
      },
      RestartPolicy: {Name: "unless-stopped"},
      NetworkMode: "custom-net",
      LogConfig: {Type: "db"}
    },
    Mounts: [
      {Type: "bind", Source: $bind_source, Destination: "/data path", RW: false, Mode: ""},
      {Type: "volume", Name: "config_volume", Source: "/var/lib/docker/volumes/config_volume/_data", Destination: "/config", RW: true, Mode: ""}
    ]
  }]')
export DOCKER_FIXTURE

# Evaluate only the output of our checked-out script with exported fake Docker.
# The test data deliberately includes command substitution; an escaping regression
# would create a marker *inside the disposable container* and fail its case.
render_recreate_hint() {
  suggestion=$("$repo_dir/container_recreate.sh" review-test)
  run_result=$(eval "$suggestion")
}
