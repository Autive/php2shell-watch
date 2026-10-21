#!/usr/bin/env bash
# Removes php2shell-watch. Keeps /var/log/php2shell-watch.log.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
if [ -f /etc/systemd/system/php2shell-watch.timer ]; then
  systemctl disable --now php2shell-watch.timer 2>/dev/null || true
  rm -f /etc/systemd/system/php2shell-watch.timer /etc/systemd/system/php2shell-watch.service
  systemctl daemon-reload
fi
rm -f /etc/cron.d/php2shell-watch /usr/local/sbin/php2shell-watch.sh /etc/php2shell-watch.conf
rm -rf /var/lib/php2shell-watch
echo "removed; log kept at /var/log/php2shell-watch.log"
