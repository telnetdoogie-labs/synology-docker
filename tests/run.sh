#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
test_tmp_dir=$(mktemp -d)
trap 'rm -rf "$test_tmp_dir"' EXIT

docker() {
  case "$1" in
    inspect)
      if [[ "${3:-}" = '--format' ]] && [[ "${MOCK_LIST_MODE:-}" = 'true' ]]; then
        printf '/web %s local\n' "$COMPOSE_PATH"
      elif [[ "${3:-}" = '--format' ]] && [[ "${MOCK_LIST_MODE:-}" = 'unmanaged' ]]; then
        printf '/review-test !---not_managed_by_compose---! local\n'
      else
        printf '%s\n' "$DOCKER_FIXTURE"
      fi
      ;;
    ps)
      [[ "${2:-}" = '-aq' ]] || return 2
      if [[ "${MOCK_LIST_MODE:-}" = 'ps_fail' ]]; then
        return 1
      fi
      printf '%s\n' "${MOCK_DOCKER_IDS:-}"
      ;;
    run)
      shift
      printf 'MOCK_DOCKER_RUN\n'
      printf '<%s>\n' "$@"
      ;;
    *)
      return 2
      ;;
  esac
}
export -f docker

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
unset RECREATE_TEST_APP RECREATE_TEST_APP_EXTRA
suggestion=$("$repo_dir/container_recreate.sh" review-test)
[[ "$suggestion" == *'docker run -d'* ]]
[[ "$suggestion" == *'--name review-test'* ]]
printf -v quoted_env '%q' "$malicious_env"
[[ "$suggestion" == *"-e $quoted_env"* ]]
[[ "$suggestion" == *'-e RECREATE_TEST_APP_EXTRA=two'* ]]
[[ "$suggestion" != *'--env-file'* && "$suggestion" != *'RECREATE_ENV_FILE'* ]]
[[ "$suggestion" == *'-p 127.0.0.1:8080:80/tcp'* ]]
[[ "$suggestion" == *'-p 8443:443/tcp'* ]]
printf -v quoted_ipv6 '%q' '[::1]:5353:53/udp'
[[ "$suggestion" == *"-p $quoted_ipv6"* ]]
printf -v quoted_volume '%q' "$malicious_source:/data path:ro"
[[ "$suggestion" == *"-v $quoted_volume"* ]]
[[ "$suggestion" == *'-v /var/lib/docker/volumes/config_volume/_data:/config'* ]]
[[ "$suggestion" == *'--log-driver local'* ]]
[[ "$suggestion" == *'-it example/test:1'* ]]
run_result=$(eval "$suggestion")
[[ "$run_result" == *'MOCK_DOCKER_RUN'* ]]
[[ "$run_result" == *'<-e>'*"<$malicious_env>"* ]]
[[ "$run_result" == *'<-e>'*'<RECREATE_TEST_APP_EXTRA=two>'* ]]
[[ "$run_result" == *'<-p>'*'<127.0.0.1:8080:80/tcp>'* ]]
[[ "$run_result" == *'<-p>'*'<8443:443/tcp>'* ]]
[[ "$run_result" == *'<-p>'*'<[::1]:5353:53/udp>'* ]]
[[ "$(grep -c '^<-p>$' <<< "$run_result")" -eq 3 ]]
[[ "$run_result" == *'<-v>'*"<$malicious_source:/data path:ro>"* ]]
[[ "$run_result" == *'<-v>'*'</var/lib/docker/volumes/config_volume/_data:/config>'* ]]
[[ "$run_result" == *'<argument with spaces>'*'<second-argument>'*"<$malicious_cmd>"* ]]
[[ "$run_result" == *'<--log-driver>'*'<local>'* ]]
[[ ! -e "$test_tmp_dir/should-not-run" && ! -e "$test_tmp_dir/should-not-run-cmd" && ! -e "$test_tmp_dir/should-not-run-env" ]]
printf 'Container recreation rendering tests passed\n'

compose_path="$test_tmp_dir/compose  file.yml"
: > "$compose_path"
MOCK_LIST_MODE=true
MOCK_DOCKER_IDS=review-list-test
export MOCK_LIST_MODE MOCK_DOCKER_IDS COMPOSE_PATH="$compose_path"
listing=$("$repo_dir/syno_docker_list_containers.sh")
[[ "$listing" == *"$compose_path"* ]]
MOCK_LIST_MODE=unmanaged
export MOCK_LIST_MODE
listing=$("$repo_dir/syno_docker_list_containers.sh")
[[ "$listing" == *'docker run -d'* ]]
[[ "$listing" == *'--log-driver local'* ]]
MOCK_LIST_MODE=empty
MOCK_DOCKER_IDS=''
export MOCK_LIST_MODE MOCK_DOCKER_IDS
listing=$("$repo_dir/syno_docker_list_containers.sh")
[[ "$listing" == *'Container'* && "$listing" != *'docker run'* ]]
MOCK_LIST_MODE=ps_fail
export MOCK_LIST_MODE
if listing=$("$repo_dir/syno_docker_list_containers.sh" 2>&1); then
  printf 'Failed Docker inventory was reported as empty\n' >&2
  exit 1
fi
[[ "$listing" == *'Could not list Docker containers'* ]]
[[ "$listing" != *'Compose_Location'* ]]
printf 'Container listing path tests passed\n'

for script in "$repo_dir"/*.sh; do
  bash -n "$script"
done
printf 'Shell syntax tests passed\n'
