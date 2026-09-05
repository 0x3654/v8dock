#!/bin/sh
# Auto-bring-up of the network for the 1C client on the mac (1C cluster in Docker).
# Scheme: hosts: server1c -> 192.0.2.10 (a "foreign" address so the client does
# not consider the server local); a route wraps it back to loopback; pf
# redirects to 127.0.0.1 where the docker-proxy listens. pf.conf is NOT edited:
# the rule is injected into the main ruleset on the fly (after rdr-anchor
# com.apple) — the anchor variant crashes with DIOCADDRULE on macOS.
/sbin/route add -host 192.0.2.10 127.0.0.1 || true

awk '/^rdr-anchor "com\.apple\/\*"/ {
         print
         # 8.3 cluster (ragent 1540 / rmngr 1541 / ras 1545 / rphost 1560:1591)
         print "rdr pass on lo0 proto tcp from any to 192.0.2.10 port 1540:1591 -> 127.0.0.1"
         # 8.5 cluster (2540 / 2541 / ras host 2545 / rphost 2560:2591)
         print "rdr pass on lo0 proto tcp from any to 192.0.2.10 port 2540:2591 -> 127.0.0.1"
         next
     } { print }' /etc/pf.conf | /sbin/pfctl -ef - >/dev/null 2>&1 || true
