#!/bin/bash
# Compose location, unmanaged hints, empty inventory, and inventory failures.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
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
DOCKER_FIXTURE=$(jq -cn --arg anon_volume "$anon_volume" '[{Name:"/review-test",Config:{Image:"example/test:1",Env:["RECREATE_TEST_APP=one","RECREATE_TEST_APP_EXTRA=two"],Entrypoint:["/entry","--entry-flag"],Cmd:["argument with spaces","second-argument"],Tty:true,OpenStdin:false},HostConfig:{PortBindings:{"80/tcp":[{HostIp:"127.0.0.1",HostPort:"8080"}]},RestartPolicy:{Name:"unless-stopped"},NetworkMode:"custom-net",LogConfig:{Type:"db"}},Mounts:[{Type:"bind",Source:"/tmp/source path",Destination:"/data path",RW:false,Mode:""},{Type:"volume",Name:"config_volume",Source:"/var/lib/docker/volumes/config_volume/_data",Destination:"/config",RW:true,Mode:""}]}]')
export DOCKER_FIXTURE
unset RECREATE_TEST_APP RECREATE_TEST_APP_EXTRA

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
