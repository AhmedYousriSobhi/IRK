# Chapter 2 - Time sync and services

About 1 hour. You work on `compute1`.

Almost everything on a Linux server is a **service** managed by `systemd`, and a cluster depends on its clocks agreeing. In this chapter you learn to look at services, read their logs, control them, and schedule a job with `cron`.

## What you will learn

- Start, stop, enable and inspect services with `systemctl` and `journalctl`.
- Check clock synchronization with `chronyc` and `timedatectl`, and repair it.
- Schedule a job with `cron`.

## Before you start

- Chapter 1 is done and `lab-verify` says `HEALTHY`.
- You are logged in to `compute1` as `vagrant` (`vagrant ssh compute1`).

## Part 1 - What is running?

```bash
systemctl list-units --type=service --state=running --no-legend | awk '{print $1}'
```

This is the list of services that are running right now. You should recognise some: `sshd` (remote login), `crond` (scheduled jobs), `chronyd` (time), `firewalld` (firewall), `rsyslog` (logging), `NetworkManager`.

Pick one and look at it:

```bash
systemctl status chronyd
```

Read the output top to bottom:

- `Loaded: ... enabled` means it **starts at boot**.
- `Active: active (running)` means it is **running now**.
- The last lines are its most recent log messages.

"Enabled" and "running" are separate. A service can be running but not enabled (it will be gone after a reboot) or enabled but not running (it should be up, but is not). Check both at once:

```bash
systemctl is-enabled chronyd crond
systemctl is-active chronyd crond
```

## Part 2 - Read the log first

Each service writes to the system journal. Ask for one service's messages:

```bash
sudo journalctl -u chronyd -n 5 --no-pager
```

You need `sudo` because your user is not in the groups that may read the journal. When something fails, **read the log before you guess**: the answer is usually in the last few lines.

## Part 3 - Time and why it matters

Clusters authenticate with timestamps. Later, in chapter 7, `munge` rejects credentials from a node whose clock is off. So check the clock:

```bash
timedatectl
chronyc tracking
chronyc sources
```

In `timedatectl` look for `System clock synchronized: yes`. `chronyc tracking` shows how far your clock is from the reference (`System time ... seconds slow of NTP time`: a few milliseconds is normal). `chronyc sources` lists the time servers; the line starting `^*` is the one in use.

Now break it, on purpose:

```bash
sudo systemctl stop chronyd
systemctl is-active chronyd
chronyc tracking
```

`chronyc` answers `506 Cannot talk to daemon`: it is only a remote control for `chronyd`. Look at `timedatectl` again. `NTP service` says `inactive`, but `System clock synchronized` may still say `yes` for a while, because it is a flag the kernel keeps. That is why you check the **service**, not only the flag.

Repair it and ask `chronyd` to correct a large offset at once:

```bash
sudo systemctl start chronyd
systemctl is-active chronyd
sudo chronyc makestep
```

`200 OK` means it worked. (`start` brings it up now; it stayed enabled, so it will also come back after a reboot.)

## Part 4 - Run something on a schedule

`cron` runs commands at set times. A job has five time fields and a command:

```text
minute hour day-of-month month day-of-week   command
  *     *        *         *        *        date >> /tmp/cron-test.log
```

Five stars mean "every minute". Install it for your own user without opening an editor:

```bash
(crontab -l 2>/dev/null; echo '* * * * * date >> /tmp/cron-test.log') | crontab -
crontab -l
```

Wait about a minute, then look:

```bash
cat /tmp/cron-test.log
```

You should see one timestamp per minute that has passed. Remove the job when you are done:

```bash
crontab -r
rm -f /tmp/cron-test.log
```

(Use `crontab -e` to edit your crontab in an editor; the commands above just do it in one line.) The system also has timers: `systemctl list-timers` shows the ones that ship with the OS.

## Clean up

Make sure `chronyd` is active and enabled, the cron job is gone (`crontab -l` says `no crontab for vagrant`), and `lab-verify` says `HEALTHY`.

## Check yourself

<details><summary>1. What is the difference between `systemctl start` and `systemctl enable`?</summary>

`start` runs the service now; `enable` makes it start at boot. `systemctl enable --now` does both.
</details>

<details><summary>2. A service shows `failed`. What do you read first?</summary>

`systemctl status <service>` for the last lines, then `sudo journalctl -u <service>` for the full story.
</details>

<details><summary>3. Why would a node with a wrong clock break a cluster?</summary>

Authentication tokens carry timestamps. A node whose clock is far off has its credentials rejected (you will see this with `munge` in chapter 7).
</details>

<details><summary>4. `chronyc tracking` says `506 Cannot talk to daemon`. What do you check?</summary>

`systemctl status chronyd`: the daemon is stopped or crashed. `chronyc` only talks to it.
</details>

## If you are stuck

`lab-verify` checks the clock and `lab-verify --fix` resynchronizes it. To get back to a clean node: `vagrant snapshot restore clean`.

## Next

[Chapter 3 - Users, groups and SSH keys](03-users-and-ssh.md)
