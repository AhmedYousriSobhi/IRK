# Chapter 5 - Name resolution and hosts

About 45 minutes. You work on `compute1`.

Nodes talk to each other by name (`login`, `compute2`), but the network only understands addresses. Something has to turn one into the other. When it goes wrong, the symptom is "Name or service not known", and the cure depends on knowing where the answer comes from.

## What you will learn

- Read `/etc/hosts` and `/etc/nsswitch.conf`, and test with `getent hosts`.
- Diagnose a name that resolves to the wrong address.
- Test connectivity layer by layer (`ping`, `ss`, `curl`, and Bash's `/dev/tcp`).

## Before you start

- Chapter 4 is done and `lab-verify` says `HEALTHY`.
- You are logged in to `compute1` as `vagrant`.

## Part 1 - Where do names come from?

```bash
cat /etc/hosts
grep '^hosts' /etc/nsswitch.conf
```

`/etc/hosts` is a plain text table: address, then names. The block between `# BEGIN hpc-lab` and `# END hpc-lab` is where this lab lists its nodes. There is no DNS server for the cluster names.

`nsswitch.conf` says **in which order** to look: `hosts: files dns myhostname`. First the files (`/etc/hosts`), then DNS, then the machine's own name. The first source that answers wins.

## Part 2 - Ask the way programs ask

```bash
getent hosts login compute2
getent hosts nosuchnode; echo "exit code: $?"
```

`getent hosts` uses the same order as every program (`ssh`, `ping`, `curl`), so it tells you what they will see. A name it cannot find gives exit code 2.

Compare with a tool that asks **only DNS**:

```bash
dig +short login
```

You may get nothing, or an address on some other network (the one Vagrant uses to reach the VM). Either way it is not the cluster's address `192.168.x.10` that `/etc/hosts` gives. Two tools, two answers, no contradiction: they look in different places. When something resolves differently in `ssh` than in `dig`, this is the first thing to check.

## Part 3 - A name pointing to the wrong place

Add an entry that points to an address nobody has:

```bash
echo '192.168.56.99 ghost' | sudo tee -a /etc/hosts
getent hosts ghost
ping -c1 -W2 ghost
```

(Use an address in your lab's network if you changed `LAB_SUBNET`; any unused address will do.) The name **resolves** (`getent` prints the address) but `ping` says `100% packet loss`: the name is fine, the address is wrong. Fix it by removing the line:

```bash
sudo sed -i '/ ghost$/d' /etc/hosts
getent hosts ghost; echo "exit code: $?"
```

The second symptom: a line **missing** gives "Name or service not known" (exit code 2 above). Both are fixed in `/etc/hosts`. In chapter 6 one of the problems is exactly this, and `lab-verify` also notices it.

## Part 4 - Is it the name, the address or the service?

When a connection fails, test one layer at a time, from the bottom:

| Layer | Question | Command |
|---|---|---|
| Name | Does it resolve? | `getent hosts login` |
| Network | Does the address answer? | `ping -c2 login` |
| Port | Is something listening? | `timeout 3 bash -c '</dev/tcp/login/22' && echo open` |
| Service | Does the program answer? | `ssh login hostname` (needs the keys from chapter 3), or `curl` for web services |

Run them for `login`:

```bash
getent hosts login
ping -c2 login
timeout 3 bash -c '</dev/tcp/login/22' && echo 'port 22: open'
timeout 3 bash -c '</dev/tcp/login/2049' && echo 'port 2049 (NFS): open'
timeout 3 bash -c '</dev/tcp/login/9999' 2>&1 | head -1
```

Port 22 (SSH) and 2049 (NFS) are open. Port 9999 prints `Connection refused`: the machine answered but nothing listens there. That is different from a **timeout** (no answer at all, often a firewall or a down host). `ss -tln` on the target lists what is listening (chapter 4); `sudo firewall-cmd --list-all` shows the firewall.

Try the same ladder against a name that does not exist (`getent hosts nosuchnode` stops at the first layer). The point of the ladder: the first layer that fails tells you where to look.

## Clean up

`/etc/hosts` should contain no `ghost` line, and `lab-verify` should say `HEALTHY`.

## Check yourself

<details><summary>1. `ping login` says "Name or service not known". What do you check?</summary>

`getent hosts login`. If it prints nothing, the name is not in `/etc/hosts` (and not in DNS). Look at the `# BEGIN hpc-lab` block.
</details>

<details><summary>2. `ping 192.168.x.10` works but `ping login` does not. What is wrong?</summary>

Name resolution. The network is fine.
</details>

<details><summary>3. What is the difference between "Connection refused" and a timeout?</summary>

Refused: the machine answered and nothing listens on that port. Timeout: no answer, which points to a firewall, a wrong address or a machine that is down.
</details>

<details><summary>4. Why can `getent hosts login` and `dig +short login` disagree?</summary>

`getent` follows `nsswitch.conf` (files first, then DNS); `dig` asks only DNS.
</details>

## If you are stuck

`lab-verify` checks that every node name resolves to the right address; `lab-verify --fix` does not edit `/etc/hosts`, so repair it by hand or with `vagrant provision <node>`.

## Next

Chapter 6: [02-troubleshooting](../../02-troubleshooting/README.md). You now have all the skills it uses.
