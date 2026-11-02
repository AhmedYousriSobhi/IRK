# 01 - Sysadmin foundations

Chapters 1 to 5, about 5 hours in total. You learn the everyday Linux administration skills that a cluster depends on, using the lab's nodes. Nothing here needs Slurm: you practice on the plain cluster that `vagrant up` builds.

This module has no tools or provisioner of its own. Everything it uses is set up by `core/`, and the health check `lab-verify` tells you whether a node is in the state the chapters expect.

## Before you start

- Chapter 0 is done: the lab is up, you can log in to `login`, and `lab-verify` reports `HEALTHY` on every node.
- You are comfortable with basic shell use (`cd`, `ls`, `cat`, editing a file with `vim` or `nano`). No prior administration experience is needed.
- Take a snapshot before chapter 1 so you can return to a clean cluster: `vagrant snapshot save clean`.

## What the cluster gives you

| Item | Where | Used in |
|---|---|---|
| Shared storage | `login` exports `/shared` over NFS; compute nodes mount it | 1, 3, 4 |
| Lab accounts | `alice`, `bob`, `carol` (same UID on every node), homes in `/shared/home` | 3, 4 |
| Groups | `hpc-users` (all users), `proj-a` (alice and bob) with the project directory `/shared/project/proj-a` | 3, 4 |
| Time sync | `chronyd` on every node | 2 |
| Services | `systemd`, `crond`, `firewalld`, SELinux in enforcing mode | 2 |
| Name resolution | cluster names in `/etc/hosts`, no DNS server | 5 |

The default password for the lab accounts is `hpclab` (see the security note in the lab README).

## Chapters

### [Chapter 1 - Storage and the shared filesystem](chapters/01-storage.md)

You find out where data lives and why a cluster shares it.

- Read disk and filesystem usage (`df`, `lsblk`, `du`, `findmnt`).
- Follow a file from one node to another through the NFS export on `login`.
- See what happens to a compute node when `/shared` is not mounted, and fix it.

### [Chapter 2 - Time sync and services](chapters/02-time-and-services.md)

You learn to inspect and control services, and why clocks matter.

- Start, stop, enable and inspect services with `systemctl` and `journalctl`.
- Check clock synchronization with `chronyc` and `timedatectl`, and repair it.
- Schedule a job with `cron`.

### [Chapter 3 - Users, groups and SSH keys](chapters/03-users-and-ssh.md)

You manage accounts the way a cluster expects them.

- Inspect users and groups (`id`, `getent`) and see why the UID must match on every node.
- Create a key pair and set up passwordless SSH between nodes.
- Use `ssh`, `scp` and `rsync` to move work around.

### [Chapter 4 - Permissions and processes](chapters/04-permissions-and-processes.md)

You control who can touch what, and what is running.

- Read and change permissions, ownership, and the setgid bit on a shared project directory.
- Find and stop processes (`ps`, `top`, `htop`, `kill`, `lsof`).
- Meet an SELinux denial, and read it instead of switching SELinux off.

### [Chapter 5 - Name resolution and hosts](chapters/05-name-resolution.md)

You learn how a node turns a name into an address.

- Read `/etc/hosts` and `/etc/nsswitch.conf`, and test with `getent hosts`.
- Diagnose a name that resolves to the wrong address.
- Test connectivity layer by layer (`ping`, `ss`, `curl`, and Bash's `/dev/tcp`).

## Check your work

Run `lab-verify` on a node after each chapter. It checks hostname, name resolution, clock, NFS, shared writes, accounts, SELinux, swap and disk, and prints what to do about each problem. `lab-verify --fix` applies the safe repairs (clock resync, remounting `/shared`).

## Reset

- Restore the snapshot from before chapter 1: `vagrant snapshot restore clean`.
- Or re-apply the base setup on a node without rebuilding it: `vagrant provision <node>`. This is safe to repeat.

## Next

Chapter 6 (module [02-troubleshooting](../02-troubleshooting/README.md)) puts these skills to work on faults you did not cause.

> **Status:** the five chapters are written. Every command in them was run on a 3-node Rocky Linux 9.3 cluster, and the output they describe is what that cluster printed. Chapters 6 to 9 live in the READMEs of modules 02, 03 and 04.
