# Troubleshooting answer key

> **Spoilers.** This file names the cause and the fix of every planted problem in module [02-troubleshooting](../modules/02-troubleshooting/README.md). Learners should not read it before they have tried the exercise: `sudo inject-fault --reveal` is the gentler hint.
>
> The repository is public and the scenarios are readable in `inject-fault.sh` on every node, so treat the exercises as practice, not as an assessment. For an exam, keep a private variant of the script with different scenarios.

For how the fault system works, how to hand out problems and how to recover, see the [admin guide](README.md).

## What is planted

"After chapter" says when a learner has the skills for that problem; chapter 6 is the practice chapter that uses all of them.

| Scenario | Runs on | Symptom the user reports | Skill practiced | After chapter |
|---|---|---|---|---|
| `disk-full` | any | Application cannot save: "No space left on device" | `df`, `du`, finding large files | 1, 6 |
| `inode-exhaustion` | any | "No space left on device" but the disk is not full | `df -i`, inode concept | 1, 6 |
| `service-stopped` | any | Cron jobs stopped running | `systemctl` status, enable vs start | 2, 6 |
| `service-failed` | any | Clock drifting, time service will not stay up | `journalctl`, config files | 2, 6 |
| `bad-permissions` | login | alice and bob get "Permission denied" in the project folder | `ls -ld`, `chgrp`, `chmod`, setgid | 4, 6 |
| `ssh-keys` | login | alice's passwordless ssh asks for a password again | `ssh -v`, `journalctl -u sshd`, key permissions | 3, 6 |
| `runaway-process` | any | Node extremely slow | `top`, `ps`, `kill`, user communication | 4, 6 |
| `locked-user` | any | bob cannot log in | `passwd -S`, `chage -l`, `usermod` | 3, 6 |
| `hosts-entry` | any | A node cannot be reached by name | `getent hosts`, `/etc/hosts`, DNS vs hosts | 5, 6 |
| `nfs-unmounted` | compute | Home directories and `/shared` look empty | `findmnt`, `/etc/fstab`, NFS | 1, 6 |

## Answer key

Each entry lists: what is planted, the ticket, how to diagnose, the fix, what `fault-status` checks, and points for the debrief.

---

### `disk-full`

**Planted:** a 64 MB filesystem (loop-mounted, no reserved space) at `/data/app`, owned by carol. It holds `config.yml`, a legitimate 12 MB `logs/app-2026.log`, and a large `logs/core.dump.tmp` that fills the rest.

**Ticket:** "The analysis application on this node cannot save its results: it reports 'No space left on device'. Nobody deleted anything. Please investigate (the application writes under /data/app)."

**Diagnose**

1. `df -h /data/app` shows the filesystem at 100%.
2. `du -sh /data/app/*` and `ls -lh /data/app/logs` show where the space went.
3. The large `core.dump.tmp` is the culprit.

**Fix:** remove (or truncate) `/data/app/logs/core.dump.tmp`.

**`fault-status` checks:** `/data/app` is still mounted and has more than 10 MB free.

**Debrief**

- Freeing the 12 MB log would also pass the check. Ask which file was safe to delete and why: a temporary dump versus an application log.
- `df` tells you which filesystem is full, `du` tells you where the data is.
- Ask what they would tell the user, and whether the dump needs investigating.

---

### `inode-exhaustion`

**Planted:** a 32 MB filesystem with about 1,000 inodes at `/data/spool`. `/data/spool/queue` is filled with empty `job-N.tmp` files until no inodes are left.

**Ticket:** "Writing new files under /data/spool fails with 'No space left on device', but the user insists the disk is not full."

**Diagnose**

1. `df -h /data/spool` shows plenty of free space.
2. `df -i /data/spool` shows inode use at 100%.
3. `ls /data/spool/queue | wc -l` shows around a thousand tiny files.

**Fix:** remove the files, for example `find /data/spool/queue -name 'job-*.tmp' -delete`.

**`fault-status` checks:** `/data/spool` is mounted and has more than 100 free inodes.

**Debrief**

- The same error message ("No space left on device") has two causes; check space and inodes.
- Ask what in a real system creates millions of tiny files (mail queues, job spools, caches), and how to prevent it.

---

### `service-stopped`

**Planted:** `crond` is stopped and disabled.

**Ticket:** "Scheduled jobs (cron) on this node stopped running since this morning, and nobody changed the crontabs."

**Diagnose:** `systemctl status crond` shows it inactive and disabled; `systemctl is-enabled crond` confirms.

**Fix:** `sudo systemctl enable --now crond`

**`fault-status` checks:** `crond` is active **and** enabled.

**Debrief**

- `systemctl start` alone leaves the service disabled, so it fails the check. This teaches the difference between running now and surviving a reboot.
- Ask how they would find out when it stopped (`journalctl -u crond`).

---

### `service-failed`

**Planted:** in `/etc/chrony.conf`, `driftfile` is misspelled as `driftfle` (or a bad line is added if no `driftfile` exists), and `chronyd` is restarted so that it fails.

**Ticket:** "This node's clock is drifting and time synchronization looks broken: 'chronyc' cannot talk to the daemon, and the service will not stay up."

**Diagnose**

1. `chronyc tracking` reports it cannot talk to the daemon.
2. `systemctl status chronyd` shows a failed unit.
3. `journalctl -u chronyd` names the unrecognized directive and its line.
4. Inspect `/etc/chrony.conf` and find the typo.

**Fix:** correct the directive, then `sudo systemctl restart chronyd`.

**`fault-status` checks:** `chronyd` is active.

**Debrief**

- Reading the log first beats guessing.
- Ask why a wrong clock matters later (chapter 7: munge rejects credentials when clocks differ).
- Suggest `chronyc makestep` after the service is back to correct a large offset.

---

### `bad-permissions` (login node only)

**Planted:** `/shared/project/proj-a` changed from `root:proj-a` mode `2770` to `root:root` mode `700`.

**Ticket:** "alice and bob (project proj-a) suddenly get 'Permission denied' in /shared/project/proj-a. It worked yesterday."

**Diagnose**

1. `ls -ld /shared/project/proj-a` shows `root root drwx------`.
2. `id alice` confirms alice is in `proj-a`.
3. The directory's group and mode no longer allow the group.

**Fix:** `sudo chgrp proj-a /shared/project/proj-a` and `sudo chmod 2770 /shared/project/proj-a`

**`fault-status` checks:** the group is `proj-a` and the group has full (rwx) access. It does not require the setgid bit or "no access for others".

**Debrief**

- `chmod 777` alone does not pass, because the group is still `root`. `chgrp` plus `chmod -R 777` does pass but is poor practice. Discuss least privilege.
- Explain what the leading `2` (setgid) does: new files inherit the group `proj-a`.
- Ask why the fix must be made on the login node (the NFS server); root on a compute node is mapped to an unprivileged user.

---

### `ssh-keys` (login node only)

**Planted:** alice's ed25519 key pair and `authorized_keys` are created if they do not exist. Then her home directory and `~/.ssh` are set to `777`, and `authorized_keys` and the private key to `666`.

**Ticket:** "alice's passwordless ssh from the login node to the compute nodes stopped working: it asks for a password now. She says she only ran a 'chmod -R 777' on her home directory."

**Diagnose**

1. As alice: `ssh -v compute1`. The client warns that the private key file is unprotected (too open) and ignores it, then falls back to the password prompt.
2. On the target node, `journalctl -u sshd` shows the server refusing the key because of bad ownership or modes for a file or directory.
3. `ls -ld ~ ~/.ssh` and `ls -l ~/.ssh` show the open permissions.

**Fix (as alice or root):** `chmod 700 ~ ~/.ssh` (755 on the home also works) and `chmod 600 ~/.ssh/authorized_keys ~/.ssh/id_ed25519`

**`fault-status` checks:** the home directory is not group- or world-writable, and `~/.ssh`, `authorized_keys` and the private key are not accessible to group or others. It checks permissions only, not an actual login.

**Debrief**

- Both sides enforce permissions: the client protects the private key, the server (StrictModes) protects `authorized_keys`.
- alice can still log in with her password, so this is not a lockout. Ask why the user noticed.
- Run this scenario after chapter 3. If alice had no keys, the tool creates them, and `--revert` removes only what it created.

---

### `runaway-process`

**Planted:** two CPU-bound shell loops owned by carol, named `postproc_job.sh`. With one vCPU per node, the node becomes sluggish.

**Ticket:** "This node has been extremely slow for the past hour: interactive commands lag and everything feels sluggish."

**Diagnose**

1. `uptime` shows a high load average.
2. `top` or `ps aux --sort=-%cpu | head` shows two processes of user `carol` using most of the CPU.
3. `ps -fu carol` shows the command name `postproc_job.sh`.

**Fix:** stop the processes, for example `sudo pkill -u carol -f postproc_job.sh`, or `kill <pid>` for each.

**`fault-status` checks:** no process of carol matching `postproc_job.sh` is running.

**Debrief**

- `renice` reduces the impact but does not fix the problem, so it fails the check.
- Killing a user's process is a decision. Ask what they would do first (contact carol, check whether it is a legitimate job) before `kill`, and when `kill -9` is justified.
- Good moment to practice the ticket note's "what you checked, in order".

---

### `locked-user`

**Planted:** `usermod -L -e 1 bob`: bob's password is locked and his account is expired. It affects only the node where it was planted.

**Ticket:** "bob cannot log in on this node, although he is sure his password is correct."

**Diagnose**

1. `passwd -S bob` shows the status as locked (`LK`).
2. `chage -l bob` shows the account expired (the expiry date is in 1970).
3. `su - bob` reports that the account has expired.

**Fix:** `sudo usermod -U bob` and `sudo usermod -e "" bob` (or `sudo chage -E -1 bob`)

**`fault-status` checks:** the account is not locked and "Account expires" is `never`.

**Debrief**

- Two separate mechanisms are in play. Fixing only one still leaves bob locked out.
- Accounts are local on each node (no LDAP in the lab), so the fix is needed on every affected node. Link this to why centralized identity matters.

---

### `hosts-entry`

**Planted:** one peer's line is removed from `/etc/hosts`. On the login node the peer is the first compute node; on a compute node it is `login`. The ticket names the node.

**Ticket:** "From this node, '<node>' cannot be reached by name ('Name or service not known'), but the machine is running."

**Diagnose**

1. `ping <node>` reports the name cannot be resolved.
2. `getent hosts <node>` returns nothing.
3. `cat /etc/hosts` shows the line missing from the `# BEGIN hpc-lab` block. The correct address is in `/etc/hpc-lab-release` (the `LAB_NODES` line), in another node's `/etc/hosts`, or in `README.md`.

**Fix:** add the line back, for example `echo "192.168.56.11 compute1" | sudo tee -a /etc/hosts`

**`fault-status` checks:** `getent hosts <node>` returns the correct IP address. A wrong address fails.

**Debrief**

- Pinging the IP address works while the name fails: that separates a network problem from a naming problem.
- `lab-verify` also fails on this node, which shows how the health check helps.
- Ask how the same symptom would appear with DNS instead of `/etc/hosts`.

---

### `nfs-unmounted` (compute nodes only)

**Planted:** the `/etc/fstab` line for `/shared` (marked `# hpc-lab mount`) is commented out and `/shared` is unmounted.

**Ticket:** "On this node the users' home directories and /shared look empty, and files users saved yesterday are 'gone'."

**Diagnose**

1. `findmnt /shared` returns nothing, and `df -h /shared` shows the local root filesystem.
2. `ls /shared` is empty.
3. `grep shared /etc/fstab` shows the commented line.
4. `showmount -e login` confirms the server still exports `/shared`.

**Fix:** remove the `#` from the `/etc/fstab` line, run `sudo systemctl daemon-reload`, then `sudo mount /shared`.

**`fault-status` checks:** `/shared` is mounted **and** the `/etc/fstab` line is active again.

**Debrief**

- A manual `mount` alone fixes the symptom but fails the check, because the fix would not survive a reboot.
- Ask what happens if a user writes into `/shared` while it is unmounted (the data lands on the local disk and is hidden when the share returns).
- The files were never gone; they live on the login node.
