#!/usr/bin/env bash
# Removes php2shell-watch. Keeps /var/log/php2shell-watch.log.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
rm -f /etc/cron.d/php2shell-watch /usr/local/sbin/php2shell-watch.sh /etc/php2shell-watch.conf
rm -rf /var/lib/php2shell-watch
echo "removed; log kept at /var/log/php2shell-watch.log"
