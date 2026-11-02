# Chapter 4 - Permissions and processes

About 1 hour. You work on `login` and `compute1`.

Two questions come up all day on a shared system: who may touch this file, and what is running on this machine? This chapter answers both, and ends with your first look at SELinux.

## What you will learn

- Read and change permissions, ownership and the setgid bit on a shared project directory.
- Find and stop processes with `ps`, `top`, `kill` and `lsof`.
- Meet an SELinux denial, and read it instead of switching SELinux off.

## Before you start

- Chapter 3 is done and `lab-verify` says `HEALTHY`.
- You are `vagrant` on `login`. As before, `sudo -iu alice` (or `bob`, `carol`) gives you a shell as that user.

## Part 1 - Reading permissions

```bash
ls -ld /shared/project/proj-a
```

You see something like `drwxrws---. 2 root proj-a`. The first ten characters are the mode, in groups:

| Characters | Who | Meaning |
|---|---|---|
| `d` | | it is a directory |
| `rwx` | the owner (`root`) | read, write and enter (`x`) |
| `rws` | the group (`proj-a`) | read, write and enter; the `s` is the **setgid bit**, shown in place of the group's `x` |
| `---` | everyone else | nothing |

(The `.` after the mode means the file has an SELinux label; you meet that in Part 4.) The third column is the owner and the fourth the group: `root` and `proj-a`.

In short: `root` and members of `proj-a` have full access, nobody else has any. As a number this is `2770`: the `2` is the setgid bit, then `7` for the owner, `7` for the group, `0` for others.

## Part 2 - A shared project folder in practice

`alice` and `bob` are in `proj-a`; `carol` is not. As alice, create a file in the project folder:

```bash
sudo -iu alice bash -c 'touch /shared/project/proj-a/alice.txt; ls -l /shared/project/proj-a/alice.txt'
```

The file is owned by `alice`, but its **group is `proj-a`**, not alice's own group. That is the setgid bit at work: new files inherit the directory's group, so the whole project can reach them.

Can bob change alice's file?

```bash
sudo -iu bob bash -c 'echo x >> /shared/project/proj-a/alice.txt; echo exit code $?'
```

No: "Permission denied" and exit code 1. The file is `-rw-r--r--`, so the group may read but not write. alice opens it up to the group:

```bash
sudo -iu alice bash -c 'chmod g+w /shared/project/proj-a/alice.txt; ls -l /shared/project/proj-a/alice.txt'
sudo -iu bob bash -c 'echo x >> /shared/project/proj-a/alice.txt; echo exit code $?'
```

Now `-rw-rw-r--` and bob's write works (exit code 0). `chmod g+w` means "for the **g**roup, **add** **w**rite". And carol?

```bash
sudo -iu carol bash -c 'ls /shared/project/proj-a'
```

"Permission denied": she is not in `proj-a`, and others have no access. The same holds from `compute1` (try it). Permissions are decided on the server, using the numeric IDs from chapter 3.

Remove your test file:

```bash
sudo rm /shared/project/proj-a/alice.txt
```

> **Least privilege.** `chmod 777` would make every problem go away, and creates a bigger one: everybody can change and delete everything. Give a group exactly the access it needs.

## Part 3 - What is running?

On `compute1`:

```bash
top -b -n1 | head -12
ps aux --sort=-%mem | head -5
```

`top` is a live view (press `q` to quit when you run it without `-b`; `htop` is a friendlier version). The header gives load average (how busy the CPUs are, per 1, 5 and 15 minutes), memory and swap. The list shows each process, its owner (`USER`) and its CPU and memory use.

Start a process, find it, and stop it:

```bash
sleep 600 &
ps -o pid,user,stat,etime,cmd -C sleep
kill $!
sleep 1; ps -C sleep || echo gone
```

`&` runs it in the background; `$!` is the number of the last background job. `kill` asks the process to end politely (signal `TERM`). Only if a process ignores that do you use `kill -9`, which cannot be refused and gives it no chance to clean up.

Which process listens on a network port, and who has a file open?

```bash
sudo ss -tlnp | head -6
sudo lsof -i :22 -sTCP:LISTEN | head -3
```

`ss -tlnp` lists listening TCP ports with the program behind each one; `lsof` shows every file or socket a process holds open (also handy for "which process still has this deleted file open?").

## Part 4 - Your first SELinux denial

SELinux is a second lock on top of permissions: even root is limited to what policy allows. Check that it is on:

```bash
getenforce
ps -eZ | grep sshd | head -2
ls -Zd /etc/passwd /usr/local/bin/inject-fault
```

`Enforcing` means it blocks. The `-Z` option adds the **context** (`user:role:type:level`); the *type* (for example `sshd_t`, `passwd_file_t`, `bin_t`) is what policy cares about.

Cause a harmless denial. Create a small script and a service that runs it, in a place SELinux does not expect programs:

```bash
sudo mkdir -p /srv/demo
printf '#!/bin/bash\necho hello from demo >> /tmp/demo.out\n' | sudo tee /srv/demo/hello.sh >/dev/null
sudo chmod 755 /srv/demo/hello.sh
printf '[Service]\nType=oneshot\nExecStart=/srv/demo/hello.sh\n' | sudo tee /etc/systemd/system/demo.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl start demo
systemctl status demo --no-pager | grep -E 'Active|Process'
```

It fails with `status=203/EXEC`: systemd could not execute the script, although the file is executable by everyone. Read the denial in the audit log:

```bash
sudo grep denied /var/log/audit/audit.log | tail -1
ls -Z /srv/demo/hello.sh
```

The line says `denied { execute }` for `scontext=...init_t` (systemd) on `tcontext=...var_t` (your script's type). In words: "systemd may not execute a file labelled `var_t`". The fix is to give the file the right label, not to switch SELinux off:

```bash
sudo chcon -t bin_t /srv/demo/hello.sh
sudo systemctl start demo
cat /tmp/demo.out
```

It works. (`chcon` is a quick change; a permanent one uses `semanage fcontext` and `restorecon`, which a real server needs.) Clean up:

```bash
sudo systemctl stop demo
sudo rm -rf /srv/demo /etc/systemd/system/demo.service /tmp/demo.out
sudo systemctl daemon-reload
```

> **Never run `setenforce 0` as a fix.** If you do that to test, put it back (`sudo setenforce 1`) and find the real cause.

## Clean up

`lab-verify` on both nodes should say `HEALTHY`. Check that `sleep` is gone and `/srv/demo` does not exist.

## Check yourself

<details><summary>1. A directory shows `drwxrws---`. What does the `s` mean and why do shared projects use it?</summary>

The setgid bit: files created inside get the directory's group instead of the creator's main group, so every member of the project can reach them.
</details>

<details><summary>2. A user says "Permission denied" in a project folder. What do you check, in order?</summary>

`ls -ld` on the folder (owner, group, mode), `id <user>` (are they in that group?), then `ls -l` on the file. On NFS, check on the server.
</details>

<details><summary>3. When do you use `kill -9`?</summary>

Only after a normal `kill` was ignored. It gives the process no chance to clean up.
</details>

<details><summary>4. A service fails with `203/EXEC` but the file is executable. What do you suspect?</summary>

SELinux. Read the denial in `/var/log/audit/audit.log` and compare the types with `ls -Z`.
</details>

## If you are stuck

If a permission change breaks something you cannot undo: `vagrant snapshot restore clean`.

## Next

[Chapter 5 - Name resolution and hosts](05-name-resolution.md)
