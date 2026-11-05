#!/bin/bash
# The best-effort hint includes inline env, local logger, and a copyable command.
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

suggestion=$("$repo_dir/container_recreate.sh" review-test)
[[ "$suggestion" == *'docker run -d'* ]]
[[ "$suggestion" == *'--name review-test'* ]]
[[ "$suggestion" == *'-e "RECREATE_TEST_APP=one"'* ]]
[[ "$suggestion" == *'-e "RECREATE_TEST_APP_EXTRA=two"'* ]]
[[ "$suggestion" == *'-p 8080:80/tcp'* ]]
[[ "$suggestion" == *'-v /tmp/source path:/data path'* ]]
[[ "$suggestion" == *'-v /var/lib/docker/volumes/config_volume/_data:/config'* ]]
[[ "$suggestion" == *'--log-driver local'* ]]
[[ "$suggestion" == *'-it example/test:1'* ]]
run_result=$(eval "$suggestion")
[[ "$run_result" == *'MOCK_DOCKER_RUN'* ]]
[[ "$run_result" == *'<-e>'*'<RECREATE_TEST_APP=one>'* ]]
[[ "$run_result" == *'<--log-driver>'*'<local>'* ]]
printf 'Container recreation rendering tests passed\n'
