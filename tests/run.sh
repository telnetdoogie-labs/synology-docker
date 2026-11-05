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

anon_volume='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
malicious_source="/tmp/source path/\$(touch $test_tmp_dir/should-not-run)"
malicious_cmd="\$(touch $test_tmp_dir/should-not-run-cmd)"
DOCKER_FIXTURE=$(jq -cn --arg anon_volume "$anon_volume" --arg bind_source "$malicious_source" --arg command_arg "$malicious_cmd" '[{Name:"/review-test",Config:{Image:"example/test:1",Env:["RECREATE_TEST_APP=UNSAFE_SECRET","RECREATE_TEST_APP_EXTRA=SECOND_SECRET"],Entrypoint:["/entry","--entry-flag"],Cmd:["argument with spaces","second-argument",$command_arg],Tty:true,OpenStdin:false},HostConfig:{PortBindings:{"80/tcp":[{HostIp:"127.0.0.1",HostPort:"8080"}]},RestartPolicy:{Name:"unless-stopped"},NetworkMode:"custom-net",LogConfig:{Type:"db"}},Mounts:[{Type:"bind",Source:$bind_source,Destination:"/data path",RW:false,Mode:""},{Type:"volume",Name:"config_volume",Source:"/var/lib/docker/volumes/config_volume/_data",Destination:"/config",RW:true,Mode:""}]}]')
export DOCKER_FIXTURE
unset RECREATE_TEST_APP RECREATE_TEST_APP_EXTRA
suggestion=$("$repo_dir/container_recreate.sh" review-test)
[[ "$suggestion" == *'docker run -d'* ]]
[[ "$suggestion" == *'--name review-test'* ]]
[[ "$suggestion" == *'# Set RECREATE_ENV_FILE'* ]]
[[ "$suggestion" == *"--env-file \"\${RECREATE_ENV_FILE:"* ]]
[[ "$suggestion" != *'UNSAFE_SECRET'* && "$suggestion" != *'SECOND_SECRET'* ]]
[[ "$suggestion" == *'-p 8080:80/tcp'* ]]
printf -v quoted_volume '%q' "$malicious_source:/data path"
[[ "$suggestion" == *"-v $quoted_volume"* ]]
[[ "$suggestion" == *'-v /var/lib/docker/volumes/config_volume/_data:/config'* ]]
[[ "$suggestion" == *'--log-driver local'* ]]
[[ "$suggestion" == *'-it example/test:1'* ]]
if (unset RECREATE_ENV_FILE; eval "$suggestion" >/dev/null 2>&1); then
  printf 'Recreate hint ran without a private env file\n' >&2
  exit 1
fi
RECREATE_ENV_FILE="$test_tmp_dir/private env"
run_result=$(eval "$suggestion")
[[ "$run_result" == *'MOCK_DOCKER_RUN'* ]]
[[ "$run_result" == *'<--env-file>'*"<$RECREATE_ENV_FILE>"* ]]
[[ "$run_result" == *'<-v>'*"<$malicious_source:/data path>"* ]]
[[ "$run_result" == *'<argument with spaces>'*'<second-argument>'* ]]
[[ "$run_result" == *"<$malicious_cmd>"* ]]
[[ "$run_result" == *'<--log-driver>'*'<local>'* ]]
[[ ! -e "$test_tmp_dir/should-not-run" && ! -e "$test_tmp_dir/should-not-run-cmd" ]]
saved_fixture=$DOCKER_FIXTURE
DOCKER_FIXTURE=$(jq '.[0].Config.Env = []' <<< "$saved_fixture")
suggestion_no_env=$("$repo_dir/container_recreate.sh" review-test)
[[ "$suggestion_no_env" != *'--env-file'* && "$suggestion_no_env" != *'RECREATE_ENV_FILE'* ]]
DOCKER_FIXTURE=$saved_fixture
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
[[ "$listing" != *'UNSAFE_SECRET'* && "$listing" != *'SECOND_SECRET'* ]]
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
