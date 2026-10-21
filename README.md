# php2shell-watch

A small cron-driven watchdog for PHP-FPM servers, written on 21 October 2026 while waiting for the PHP emergency release for CVE-2026-109618 and CVE-2026-109619 ("php2shell"). It looks for the two things that bug would leave behind: crashed FPM workers from failed exploit attempts, and the processes, connections and files a successful one creates.

It is a single bash script with no dependencies beyond coreutils, `ss`, `ps` and optionally `python3` for the Slack payload. It is not a replacement for patching. Upgrade PHP as soon as the fixed versions (8.5.12, 8.4.27, 8.3.36, 8.2.35) are available in your repository.

Built for Debian and Ubuntu servers where each site runs its own PHP-FPM pool under its own user (Ploi, Forge, RunCloud and similar). It also runs on RHEL-style hosts such as Amazon Linux 2023, where PHP runs as `apache` or `nginx`, the FPM log is `/var/log/php-fpm/error.log`, web roots live in `/var/www`, and there is no cron daemon: the installer then uses a systemd timer instead. With a single shared PHP user the per-site-user checks are less precise, but the crash, child-process, network and file checks work the same.

## What it checks

Every 5 minutes:

1. **FPM worker crashes.** New `exited on signal 11/6/7` lines in `/var/log/php*-fpm.log`. A clean server has none; a failed use-after-free attempt produces one per request.
2. **Children of php-fpm.** Any process whose parent is a php-fpm worker. This is the webshell or reverse shell itself.
3. **Shells and network tools owned by site users** (`sh`, `bash`, `curl`, `wget`, `nc`, `socat`, `perl`, `python`, ...) that are not descended from cron, sshd, sudo, supervisord or systemd. Queue workers and scheduled jobs stay quiet.
4. **Network.** Established connections from php-fpm to ports other than 80, 443, 25, 465, 587, 53, 3306, 5432, 6379 and 11211, and any site user listening on a port.
5. **New files.** PHP files created in the last 6 minutes in `wp-content/uploads`, `wp-content/cache`, `wp-content/upgrade` and Laravel `storage/` (excluding compiled views), plus new files in `/tmp`, `/var/tmp` and `/dev/shm` owned by non-system users, excluding PHP's own upload and session temp files.
6. **Persistence.** Changes to user crontabs, `/etc/cron.d` and every `authorized_keys`, reported as a diff against the previous run.

Findings go to `/var/log/php2shell-watch.log` and syslog, and optionally to a Slack incoming webhook or a mail address. An identical finding is forwarded at most once per hour.

## Install

```sh
git clone https://github.com/Autive/php2shell-watch.git
cd php2shell-watch
sudo ./install.sh
```

The installer copies the script to `/usr/local/sbin`, schedules it every 5 minutes (through `/etc/cron.d/php2shell-watch` when a cron daemon runs, otherwise through `php2shell-watch.timer` in systemd), creates `/etc/php2shell-watch.conf` from the example, takes a baseline, and runs once verbosely so you see the current state immediately.

Then put a Slack webhook or mail address in `/etc/php2shell-watch.conf`.

## Tuning

If a site legitimately spawns processes from PHP (an image plugin calling `convert`, for instance), add them to `IGNORE_CHILDREN` in the conf as a regex. Noisy paths go in `IGNORE_PATHS`. Legitimate listeners run by a site user (the Laravel Nightwatch agent is ignored by default) go in `IGNORE_LISTEN`. Shells a site user legitimately starts detached from a web request (Matomo's `marketplace:warm-cache` warmer is ignored by default) go in `IGNORE_SHELLS`. If your FPM logs or web roots live somewhere unusual, set `FPM_LOGS` and `WEB_ROOTS`.

Manual runs:

```sh
sudo php2shell-watch.sh -v       # run now, also print "no findings"
sudo php2shell-watch.sh --init   # reset the baseline without alerting
```

## Mitigation drop-in

`disable-upload-progress.sh` sets `session.upload_progress.enabled = Off` for every installed PHP version through a conf.d drop-in and reloads FPM. Leaked analyses place one of the two bugs in that handler; researchers say it does not cover the other, so treat it as a stopgap, not a fix. Uploads keep working; only progress bars that poll `$_SESSION` stop.

```sh
sudo ./disable-upload-progress.sh
```

## Uninstall

```sh
sudo ./uninstall.sh
```

## License

MIT.
