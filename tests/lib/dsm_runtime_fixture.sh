#!/bin/bash
# Common simulated DSM environment for the standalone runtime-probe cases.
# Source after test_env.sh, which enforces the disposable-image guard and supplies
# repo_dir/test_tmp_dir. These are intentionally inherited from that fixture.
# shellcheck disable=SC2154

prepare_dsm_runtime_fixture() {
  init_update_fixture

  probe_bin="$test_tmp_dir/runtime-probe-bin"
  mkdir -p "$probe_bin" /etc.defaults

  # Link real tools when available; supply harmless stand-ins for utilities
  # whose presence the probe checks but the Debian test image may lack.
  local tool tool_path
  for tool in bash jq realpath readlink timeout mktemp awk; do
    tool_path=$(type -P "$tool" || true)
    [[ -n "$tool_path" ]] || { printf 'Required test utility missing: %s\n' "$tool" >&2; return 1; }
    ln -s "$tool_path" "$probe_bin/$tool"
  done
  for tool in comm sort sed tar find diff date curl docker insmod lsmod iptables sha256sum; do
    tool_path=$(type -P "$tool" || true)
    if [[ -n "$tool_path" ]]; then
      ln -s "$tool_path" "$probe_bin/$tool"
    else
      printf '#!/bin/sh\nexit 0\n' > "$probe_bin/$tool"
      chmod +x "$probe_bin/$tool"
    fi
  done

  cat > /usr/syno/bin/synopkg <<'EOF'
#!/bin/sh
exit 0
EOF
  cat > /usr/syno/sbin/synoservicectl <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x /usr/syno/bin/synopkg /usr/syno/sbin/synoservicectl
}

set_mock_dsm_version() {
  printf 'majorversion="%s"\nproductversion="%s"\n' "$1" "$2" > /etc.defaults/VERSION
}

run_runtime_probe() {
  PATH="$probe_bin:$PATH" sh "$repo_dir/tests/check-dsm-runtime.sh" "$1"
}
