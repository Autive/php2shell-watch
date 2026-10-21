#!/usr/bin/env bash
# Installs php2shell-watch on this server. Run as root from the repo directory:
#   sudo ./install.sh
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

install -m 750 "$dir/php2shell-watch.sh" /usr/local/sbin/php2shell-watch.sh
bash -n /usr/local/sbin/php2shell-watch.sh

if [ ! -f /etc/php2shell-watch.conf ]; then
  install -m 600 "$dir/php2shell-watch.conf.example" /etc/php2shell-watch.conf
fi

printf '*/5 * * * * root /usr/local/sbin/php2shell-watch.sh >/dev/null 2>&1\n' > /etc/cron.d/php2shell-watch
chmod 644 /etc/cron.d/php2shell-watch

echo "fpm logs watched: $(ls /var/log/php*-fpm.log 2>/dev/null | tr '\n' ' ')"
/usr/local/sbin/php2shell-watch.sh --init
/usr/local/sbin/php2shell-watch.sh -v
echo "installed; edit /etc/php2shell-watch.conf to add a Slack webhook or mail address"
