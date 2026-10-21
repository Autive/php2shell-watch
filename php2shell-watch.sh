#!/usr/bin/env bash
# php2shell-watch: flags exploit attempts and post-exploitation on PHP-FPM servers.
# Runs as root from /etc/cron.d/php2shell-watch every 5 minutes.
# Reports to /var/log/php2shell-watch.log, syslog and optionally Slack/mail (see /etc/php2shell-watch.conf).
#   php2shell-watch.sh          normal run (silent when nothing is found)
#   php2shell-watch.sh -v       also print "no findings"
#   php2shell-watch.sh --init   take the baseline (log positions, crontab/ssh hashes) without alerting
set -u
CONF=/etc/php2shell-watch.conf
STATE=/var/lib/php2shell-watch
LOG=/var/log/php2shell-watch.log
SLACK_WEBHOOK=""; MAIL_TO=""; IGNORE_CHILDREN=""; IGNORE_PATHS=""
[ -f "$CONF" ] && . "$CONF"
mkdir -p "$STATE"
HOST=$(hostname -s)
INIT=0; VERBOSE=0
[ "${1:-}" = "--init" ] && INIT=1
[ "${1:-}" = "-v" ] && VERBOSE=1
findings=()
add() { findings+=("$1"); }

# Site users = owners of php-fpm pools (one user per site on Ploi/Forge-style hosts)
ps -eo pid,ppid,user:32,comm,args --no-headers > "$STATE/ps.txt"
site_users=$(awk '$4 ~ /^php-fpm/ && $3 != "root" {print $3}' "$STATE/ps.txt" | sort -u)
fpm_pids=" $(awk '$4 ~ /^php-fpm/ {print $1}' "$STATE/ps.txt" | tr '\n' ' ')"

# 1. Crashing FPM workers (a failed use-after-free attempt = SIGSEGV/SIGABRT/SIGBUS)
for f in /var/log/php*-fpm.log; do
  [ -f "$f" ] || continue
  key=$(basename "$f"); prev=$(cat "$STATE/lines_$key" 2>/dev/null || echo 0)
  cur=$(wc -l < "$f"); [ "$cur" -lt "$prev" ] && prev=0
  echo "$cur" > "$STATE/lines_$key"
  [ $INIT -eq 1 ] && continue
  hits=$(tail -n +$((prev+1)) "$f" | grep -E 'exited on signal (6|7|11)' | head -5)
  [ -n "$hits" ] && add "FPM workers crashed ($key):"$'\n'"$hits"
done

# 2. Child processes of php-fpm (webshell, reverse shell, downloader)
kids=$(awk -v f="$fpm_pids" '$4 !~ /^php-fpm/ && index(f, " "$2" ") {print}' "$STATE/ps.txt" | head -10)
[ -n "$IGNORE_CHILDREN" ] && kids=$(printf '%s\n' "$kids" | grep -Ev "$IGNORE_CHILDREN")
[ -n "$kids" ] && add "Process spawned by php-fpm (pid ppid user comm args):"$'\n'"$kids"

# 3. Shells/network tools owned by site users that do not come from cron/ssh/supervisor
ancestor_ok() {  # true when an ancestor is cron/sshd/supervisor/systemd
  local p=$1 i c
  for i in 1 2 3 4; do
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); [ -z "$p" ] || [ "$p" -le 1 ] && return 1
    c=$(ps -o comm= -p "$p" 2>/dev/null)
    case "$c" in cron|CRON|crond|sshd|sudo|su|supervisord|systemd|tmux*|screen) return 0;; esac
  done
  return 1
}
shells=""
for u in $site_users; do
  while read -r pid ppid user comm args; do
    ancestor_ok "$pid" || shells+="$pid $user $comm ${args:0:120}"$'\n'
  done < <(awk -v u="$u" '$3 == u && $4 ~ /^(sh|bash|dash|zsh|curl|wget|nc|ncat|netcat|socat|perl|python[0-9.]*|ruby|telnet|busybox)$/' "$STATE/ps.txt")
done
[ -n "$shells" ] && add "Shell/network tool of a site user outside cron/ssh:"$'\n'"$shells"

# 4a. Outbound connections from php-fpm to unusual ports
conns=$(ss -tnpH state established 2>/dev/null | grep 'php-fpm' | awk '{print $4}' \
  | grep -Ev '^(127\.|\[::1\]|\[::ffff:127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' \
  | grep -Ev ':(80|443|25|465|587|53|3306|5432|6379|11211)$' | sort | uniq -c | head -10)
[ -n "$conns" ] && add "php-fpm connects to unusual ports (count peer):"$'\n'"$conns"

# 4b. Listening sockets owned by site users (bind shell)
listen=""
for p in $(ss -tulnpH 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
  u=$(ps -o user:32= -p "$p" 2>/dev/null | tr -d ' '); c=$(ps -o comm= -p "$p" 2>/dev/null)
  [ -z "$u" ] && continue
  case "$c" in php-fpm*|nginx|apache2|httpd|caddy|litespeed) continue;; esac
  printf '%s\n' "$site_users" | grep -qx "$u" && listen+="pid $p $u $c: $(ss -tulnpH | grep "pid=$p," | awk '{print $5}' | tr '\n' ' ')"$'\n'
done
[ -n "$listen" ] && add "Site user listening on a port:"$'\n'"$listen"

# 5. New PHP files in upload/cache dirs and new files in tmp owned by site users
newf=$( {
  find /home -xdev \( -path '*/wp-content/uploads/*' -o -path '*/wp-content/cache/*' -o -path '*/wp-content/upgrade/*' \) -type f -name '*.ph*' -mmin -6 2>/dev/null
  find /home -xdev -path '*/storage/*' -not -path '*/storage/framework/*' -type f -name '*.php' -mmin -6 2>/dev/null
  find /tmp /var/tmp /dev/shm -xdev -type f -uid +999 -mmin -6 ! -name 'php??????' ! -name 'sess_*' -not -path '*/systemd-private-*' 2>/dev/null
} | head -10)
[ -n "$IGNORE_PATHS" ] && newf=$(printf '%s\n' "$newf" | grep -Ev "$IGNORE_PATHS")
[ -n "$newf" ] && add "New/changed suspicious files (last 6 min):"$'\n'"$(ls -la $newf 2>/dev/null)"

# 6. Persistence: crontabs, cron.d, authorized_keys
md5sum /var/spool/cron/crontabs/* /etc/cron.d/* /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null | sort > "$STATE/persist.new"
if [ $INIT -eq 0 ] && [ -f "$STATE/persist.md5" ] && ! cmp -s "$STATE/persist.md5" "$STATE/persist.new"; then
  add "Crontab/cron.d/authorized_keys changed:"$'\n'"$(diff "$STATE/persist.md5" "$STATE/persist.new" | grep '^[<>]' | head -10)"
fi
mv "$STATE/persist.new" "$STATE/persist.md5"

[ $INIT -eq 1 ] && { echo "$HOST: baseline taken"; exit 0; }
if [ ${#findings[@]} -eq 0 ]; then
  [ $VERBOSE -eq 1 ] && echo "$HOST: no findings"
  exit 0
fi

msg="php2shell-watch $HOST $(date '+%d-%m %H:%M'):"
for f in "${findings[@]}"; do msg+=$'\n\n'"$f"; done
printf '%s\n---\n' "$msg" >> "$LOG"
[ $VERBOSE -eq 1 ] && printf '%s\n' "$msg"

# Dedupe: forward the same finding at most once per hour
sig=$(printf '%s' "${findings[*]}" | md5sum | cut -c1-32)
now=$(date +%s); lastsig=$(cat "$STATE/last_sig" 2>/dev/null || true); lastt=$(cat "$STATE/last_sig_t" 2>/dev/null || echo 0)
[ "$sig" = "$lastsig" ] && [ $((now-lastt)) -lt 3600 ] && exit 0
echo "$sig" > "$STATE/last_sig"; echo "$now" > "$STATE/last_sig_t"

logger -t php2shell-watch "$(printf '%s' "$msg" | head -c 900 | tr '\n' ' ')"
if [ -n "$SLACK_WEBHOOK" ] && command -v python3 >/dev/null; then
  payload=$(printf '%s' "$msg" | head -c 3500 | python3 -c 'import json,sys;print(json.dumps({"text":"```"+sys.stdin.read()+"```"}))')
  curl -fsS -m 10 -X POST -H 'Content-Type: application/json' -d "$payload" "$SLACK_WEBHOOK" >/dev/null 2>&1 || echo "slack post failed" >> "$LOG"
fi
if [ -n "$MAIL_TO" ] && command -v sendmail >/dev/null; then
  printf 'Subject: [php2shell-watch] %s\nTo: %s\n\n%s\n' "$HOST" "$MAIL_TO" "$msg" | sendmail "$MAIL_TO"
fi
exit 0
