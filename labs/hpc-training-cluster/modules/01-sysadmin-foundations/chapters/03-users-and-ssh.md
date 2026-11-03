# Chapter 3 - Users, groups and SSH keys

About 1.5 hours. You work on `login` and `compute1`.

On a cluster, a person is the same user on every node, and moves between nodes without typing a password. This chapter shows why user IDs must match, how to look people up, and how to set up passwordless SSH.

## What you will learn

- Inspect users and groups (`id`, `getent`) and see why the UID must match on every node.
- Create a key pair and set up passwordless SSH between nodes.
- Use `ssh`, `scp` and `rsync` to move work around.

## Before you start

- Chapter 2 is done and `lab-verify` says `HEALTHY`.
- You are logged in to `login` as `vagrant`. The lab accounts are `alice`, `bob` and `carol`; their password is `hpclab`. You can become one without a password: `sudo -iu alice` starts a login shell as alice, and `exit` returns you.

## Part 1 - Who are the users?

```bash
id alice
id carol
getent passwd alice
getent group hpc-users proj-a
```

`id` shows a user's number (UID), main group and all groups. `getent` asks the system's databases the way every program does, so it also finds users that do not live in `/etc/passwd`. You should see that `alice` and `bob` belong to `hpc-users` and `proj-a`, and `carol` only to `hpc-users`.

List the human and service accounts:

```bash
getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1":"$3}'
```

The lab accounts have UIDs 2001 to 2003. Now compare with `compute1`:

```bash
id alice          # on compute1: the same UID and groups
```

## Part 2 - Why the UID must match

Files store a **number**, not a name. NFS sends that number between nodes. If two nodes disagree about who owns number 2004, files end up in the wrong hands. See it happen. On `login`:

```bash
sudo useradd -u 2004 -m -d /home/dave dave
sudo -u dave touch /shared/scratch/dave.txt
ls -l /shared/scratch/dave.txt
```

On `compute1`, which has never heard of `dave`:

```bash
ls -l /shared/scratch/dave.txt
id dave
```

The owner shows up as `2004`, a bare number, and `id dave` says there is no such user. Give `compute1` the same user with the same UID:

```bash
sudo useradd -u 2004 -m -d /home/dave dave
ls -l /shared/scratch/dave.txt
```

Now the name `dave` appears. Had `compute1` given 2004 to someone else, that person would own dave's file. This is why clusters use central accounts or a strict UID plan (this lab uses a fixed plan).

Clean up on **both** nodes, and remove the file on `login`:

```bash
sudo userdel -r dave           # on compute1, then on login
sudo rm /shared/scratch/dave.txt      # on login
```

## Part 3 - Passwordless SSH

Becoming alice on `login`:

```bash
sudo -iu alice
```

Create a key pair. Press Enter for an empty passphrase (this is a lab; on real systems a passphrase or an agent is normal):

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C alice@lab
ls -l ~/.ssh
```

You now have a **private** key (`id_ed25519`, never share it) and a **public** key (`id_ed25519.pub`, safe to hand out). To let this key log in, the public key must be listed in `~/.ssh/authorized_keys` on the target machine:

```bash
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Alice's home directory is on `/shared`, so every node sees the same `~/.ssh`. On a cluster without shared homes you would copy the public key to each node (with `ssh-copy-id`). Here one `cat` is enough.

> **Permissions matter.** SSH refuses keys when the private key or the `.ssh` directory can be read or written by others. `~/.ssh` should be `700` and the private key and `authorized_keys` `600`. In chapter 6 this is one of the problems you will have to find.

Log in to `compute1` without a password:

```bash
ssh compute1 hostname
```

The first time, SSH asks `Are you sure you want to continue connecting?`. That is it showing you the machine's host key for the first time: type `yes`. After that it remembers (`~/.ssh/known_hosts`). The command prints `compute1`. Look around while connected:

```bash
ssh compute1 'id -un; pwd'
```

You are alice on `compute1`, in the same home directory.

## Part 4 - Moving files

Still as alice:

```bash
echo 'results' > ~/notes.txt
scp ~/notes.txt compute1:/tmp/notes-copy.txt
ssh compute1 cat /tmp/notes-copy.txt
rsync -av ~/notes.txt compute1:/tmp/
ssh compute1 rm -f /tmp/notes-copy.txt /tmp/notes.txt
```

`scp` copies a file. `rsync` copies only what changed and is the usual choice for large directories (add `-n` first for a dry run). Both use the same SSH keys.

## Clean up

Remove what you made, as alice, then leave her shell:

```bash
rm -rf ~/.ssh ~/notes.txt
exit
```

You are `vagrant` again. Run `lab-verify` on both nodes.

## Check yourself

<details><summary>1. `ls -l` on a compute node shows a file owned by `2004` instead of a name. What does that tell you?</summary>

That node has no user with UID 2004 (or the UID differs from the node that created the file). UIDs must match on every node that shares storage.
</details>

<details><summary>2. Which key file do you copy to another machine, and which do you never share?</summary>

Copy the public key (`.pub`) into `authorized_keys`. Never share the private key.
</details>

<details><summary>3. SSH asks for a password although you set up your key. Name two things to check.</summary>

Permissions on the home directory, `~/.ssh`, `authorized_keys` and the private key (too open means ignored), and that the public key is really in `authorized_keys` on the target. `ssh -v` shows what it tried.
</details>

<details><summary>4. Why did one `cat >> authorized_keys` on `login` work for `compute1`?</summary>

Because alice's home directory is on the shared filesystem, so both nodes read the same file.
</details>

## If you are stuck

`lab-verify` checks accounts and groups on every node. To start the chapter again: `vagrant snapshot restore clean`.

## Next

[Chapter 4 - Permissions and processes](04-permissions-and-processes.md)
