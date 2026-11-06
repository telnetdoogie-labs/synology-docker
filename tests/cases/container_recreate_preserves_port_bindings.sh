#!/bin/bash
# Recreate hints should preserve address-family and nonempty host-port bindings.
# shellcheck source=tests/lib/test_env.sh
source "$(dirname "$0")/../lib/test_env.sh"
# shellcheck source=tests/lib/container_fixture.sh
source "$(dirname "$0")/../lib/container_fixture.sh"
# shellcheck source=tests/lib/recreate_hint_fixture.sh
source "$(dirname "$0")/../lib/recreate_hint_fixture.sh"

# Arrange: one loopback IP, one unspecified IP, one IPv6 IP, and two empty ports.
# Act: render the suggestion and replay it against fake Docker.
render_recreate_hint
printf -v quoted_ipv6 '%q' '[::1]:5353:53/udp'

# Expect: each usable binding has the right host address and arrives as one arg.
expect_contains "$suggestion" '-p 127.0.0.1:8080:80/tcp' 'preserves IPv4 loopback binding'
expect_contains "$suggestion" '-p 8443:443/tcp' 'preserves port without a host IP'
expect_contains "$suggestion" "-p $quoted_ipv6" 'quotes the IPv6 loopback binding'
expect_contains "$run_result" '<127.0.0.1:8080:80/tcp>' 'passes IPv4 binding to Docker'
expect_contains "$run_result" '<8443:443/tcp>' 'passes host port to Docker'
expect_contains "$run_result" '<[::1]:5353:53/udp>' 'passes IPv6 binding to Docker'
port_count=$(grep -c '^<-p>$' <<< "$run_result")
expect_eq 3 "$port_count" 'skips both empty host ports'
