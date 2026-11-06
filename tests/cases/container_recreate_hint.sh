#!/bin/bash
# The best-effort hint should preserve safe argv for env, ports, mounts, and Cmd.
# It does not promise a complete, lossless container recreation.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"

# Arrange: model hostile-but-valid values and three port binding forms.
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"

test_tmp_dir=$(mktemp -d)
trap 'rm -rf "$test_tmp_dir"' EXIT
malicious_source="/tmp/source path/\$(touch $test_tmp_dir/should-not-run)"
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

# Act: render the hint, then execute it only against the exported fake Docker.
suggestion=$("$repo_dir/container_recreate.sh" review-test)
printf -v quoted_env '%q' "$malicious_env"
printf -v quoted_ipv6 '%q' '[::1]:5353:53/udp'
printf -v quoted_volume '%q' "$malicious_source:/data path:ro"

# Expect: shell-quoted arguments preserve binding, mount, env, and command data.
expect_contains "$suggestion" 'docker run -d' 'renders a detached docker run'
expect_contains "$suggestion" '--name review-test' 'retains container name'
expect_contains "$suggestion" "-e $quoted_env" 'quotes inline environment data'
expect_contains "$suggestion" '-e RECREATE_TEST_APP_EXTRA=two' 'retains second environment value'
expect_contains "$suggestion" '-p 127.0.0.1:8080:80/tcp' 'preserves loopback binding'
expect_contains "$suggestion" '-p 8443:443/tcp' 'preserves host port without an IP'
expect_contains "$suggestion" "-p $quoted_ipv6" 'preserves IPv6 binding'
expect_contains "$suggestion" "-v $quoted_volume" 'quotes spaced read-only bind mount'
expect_contains "$suggestion" '-v /var/lib/docker/volumes/config_volume/_data:/config' 'retains named volume'
expect_contains "$suggestion" '--log-driver local' 'replaces db logger with local'
expect_contains "$suggestion" '-it example/test:1' 'retains image and TTY'
if [[ "$suggestion" == *'--env-file'* || "$suggestion" == *'RECREATE_ENV_FILE'* ]]; then
  printf 'FAIL: recreation hint unexpectedly uses env file\n' >&2
  exit 1
fi
run_result=$(eval "$suggestion")
expect_contains "$run_result" 'MOCK_DOCKER_RUN' 'rendered command invokes fake Docker'
expect_contains "$run_result" "<$malicious_env>" 'passes environment value as one argument'
expect_contains "$run_result" '<RECREATE_TEST_APP_EXTRA=two>' 'passes second environment value'
expect_contains "$run_result" '<127.0.0.1:8080:80/tcp>' 'passes loopback binding'
expect_contains "$run_result" '<8443:443/tcp>' 'passes host port'
expect_contains "$run_result" '<[::1]:5353:53/udp>' 'passes IPv6 binding'
expect_contains "$run_result" '<argument with spaces>' 'preserves spaced command argument'
expect_contains "$run_result" '<second-argument>' 'preserves following command argument'
expect_contains "$run_result" "<$malicious_source:/data path:ro>" 'passes read-only spaced mount as one argument'
expect_contains "$run_result" '</var/lib/docker/volumes/config_volume/_data:/config>' 'passes named volume'
expect_contains "$run_result" "<$malicious_cmd>" 'passes command data without evaluating it'
expect_contains "$run_result" '<--log-driver>' 'passes logger option'
expect_contains "$run_result" '<local>' 'passes local logger'
port_count=$(grep -c '^<-p>$' <<< "$run_result")
if [[ "$port_count" -ne 3 ]]; then
  printf 'FAIL: expected exactly three nonempty host-port bindings, found %s\n' "$port_count" >&2
  exit 1
fi
if [[ -e "$test_tmp_dir/should-not-run" || -e "$test_tmp_dir/should-not-run-cmd" || -e "$test_tmp_dir/should-not-run-env" ]]; then
  printf 'FAIL: recreation hint executed injected shell commands\n' >&2
  exit 1
fi
printf 'Container recreation rendering tests passed\n'
