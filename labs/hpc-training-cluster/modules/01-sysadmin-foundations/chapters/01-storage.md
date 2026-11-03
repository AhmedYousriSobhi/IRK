# Chapter 1 - Storage and the shared filesystem

About 1 hour. You work on `login` and `compute1`.

A cluster is many computers that must see the same files. In this chapter you find out where data lives on a node, how the compute nodes get `/shared` from the login node, and what goes wrong when that link breaks.

## What you will learn

- Read disk and filesystem usage with `lsblk`, `df`, `du` and `findmnt`.
- Follow a file from one node to another through the NFS export on `login`.
- See what happens to a compute node when `/shared` is not mounted, and fix it.

## Before you start

- Chapter 0 is done and `lab-verify` says `HEALTHY` on every node.
- You have a snapshot to return to: `vagrant snapshot save clean`.
- Open two terminals on your host, in the lab folder: one for `vagrant ssh login`, one for `vagrant ssh compute1`. You are the user `vagrant`, who can use `sudo`.

Commands are shown with the node they run on. Your numbers will differ; the shape of the output is what matters.

## Part 1 - Where does data live?

On `login`:

```bash
lsblk
df -hT -x tmpfs -x devtmpfs
```

`lsblk` lists the disks. You should see one disk (`vda`) split into a small `/boot` partition and one big partition that holds the root filesystem `/` and swap. `df -hT` lists the filesystems that are mounted, with their type (`xfs`) and how full they are. `-h` means "human readable" and `-x` leaves out the in-memory ones you do not care about.

Now ask who is using the space. `du` adds up the size of a directory:

```bash
sudo du -h --max-depth=1 /var | sort -h | tail -4
```

`sort -h` sorts human-readable sizes, so the biggest directory is last. Two rules for later: `df` tells you **which filesystem** is full, and `du` tells you **where inside it** the data is.

## Part 2 - What is `/shared`?

Still on `login`:

```bash
findmnt /shared
df -h /shared
sudo exportfs -v
```

`findmnt /shared` prints nothing. On the login node `/shared` is just a directory on the root filesystem, and `df` shows the root filesystem. `exportfs` shows why it matters: the login node **exports** `/shared` over NFS to the cluster's network (`192.168.x.0/24`).

Now on `compute1`:

```bash
findmnt /shared
df -h /shared
showmount -e login
grep shared /etc/fstab
```

Here `findmnt` shows a line with `login:/shared` and type `nfs4`, and `df` shows the **login node's** disk size under the name `login:/shared`. `showmount` lists what the server offers. The `/etc/fstab` line is what mounts it at boot (`_netdev` means "wait for the network first").

So the same directory is really one directory, on `login`, shown on every node.

## Part 3 - Follow a file across nodes

On `login`:

```bash
echo 'hello from login' > /shared/scratch/hello.txt
ls -l /shared/scratch/hello.txt
```

On `compute1`:

```bash
cat /shared/scratch/hello.txt
echo 'hello from compute1' >> /shared/scratch/hello.txt
```

Back on `login`:

```bash
cat /shared/scratch/hello.txt
```

You see both lines. One file, edited from two machines. `/shared/scratch` is open to everyone (mode `1777`, the same idea as `/tmp`), so any user can create files there.

> **Try it, then think:** repeat Part 3 using `sudo` for the `echo` on `compute1`. It fails with "Permission denied", even though `sudo` makes you root. And `sudo touch /shared/scratch/x` works, but `ls -l` shows the file is owned by `nobody` (remove such a file with `sudo rm` on `login`). NFS maps root on a compute node to an unprivileged user (this is called *root squash*). That is why you fix permissions on the NFS server, not on the clients. You will meet it again in chapter 4.

## Part 4 - When `/shared` is not mounted

This is the problem users report as "my files are gone". On `compute1`:

```bash
sudo umount /shared
ls /shared
findmnt /shared; echo "findmnt exit code: $?"
df -h /shared
```

`/shared` is now empty, `findmnt` finds nothing (exit code 1) and `df` shows the **local** root disk instead of `login:/shared`. The files are not gone: they never left `login`.

Now make the classic mistake. Write something while the share is unmounted:

```bash
sudo mkdir -p /shared/scratch
echo 'written to the local disk' | sudo tee /shared/scratch/local.txt
```

Fix the mount, which uses the line in `/etc/fstab`:

```bash
sudo mount /shared
ls /shared/scratch
```

You see `hello.txt` again, but **not** `local.txt`. It still exists on the local disk, hidden underneath the mounted share. Remove it so it cannot confuse anyone later:

```bash
sudo umount /shared
sudo rm -rf /shared/scratch
sudo mount /shared
```

The lesson: a mount point that is empty looks the same as a mount point that is not mounted. Always check with `findmnt` or `df`, not just `ls`.

## Clean up

On `login`, remove the test file (root on `compute1` is squashed, so do it where the file lives, as the user who made it):

```bash
rm /shared/scratch/hello.txt
```

Run `lab-verify` on `login` and `compute1`. Both should say `HEALTHY`.

## Check yourself

<details><summary>1. A user says their files disappeared on `compute1`. What is your first command?</summary>

`findmnt /shared` (or `df -h /shared`). If it prints nothing, or `df` shows the local disk, the share is not mounted. Then check `/etc/fstab` and `showmount -e login`.
</details>

<details><summary>2. `df -h` shows a filesystem at 100%. Which command shows where the space went?</summary>

`du -h --max-depth=1 <mount point> | sort -h`, repeated on the biggest directory until you find it.
</details>

<details><summary>3. Why does `sudo touch /shared/home/x` fail on `compute1` but work on `login`?</summary>

On the NFS server `login`, root is root. On a client, NFS squashes root to an unprivileged user (`nobody`), so the server refuses to give it special rights in a directory only root may write to. (In the open `/shared/scratch` the same `sudo touch` succeeds, but the new file is owned by `nobody`, not root.)
</details>

<details><summary>4. After you remount `/shared`, a file you wrote while it was unmounted has vanished. Where is it?</summary>

On the local disk, underneath the mount point. Unmount to see it again.
</details>

## If you are stuck

- `/shared` will not mount: check `showmount -e login` from `compute1`. If it fails, the problem is on `login` (`systemctl status nfs-server`).
- Something looks wrong and you cannot undo it: `lab-verify --fix` repairs the safe things, or restore the snapshot: `vagrant snapshot restore clean`.

## Next

[Chapter 2 - Time sync and services](02-time-and-services.md)
