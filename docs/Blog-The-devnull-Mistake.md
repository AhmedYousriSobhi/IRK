# The day I replaced /dev/null and killed SSH

*A short post-mortem from building the `hpc-training-cluster` lab. Written for engineers who test scripts on disposable VMs, and for learners who will soon break things on purpose in chapter 6.*

## What happened

I was testing the troubleshooting tools on a three-node lab cluster. Before copying updated scripts to the nodes, I ran this on two of them, `login` and `compute1`, through `vagrant ssh`:

```bash
sudo install -m0755 /dev/stdin /dev/null
```

I meant it as a throwaway "does sudo work here?" probe. It was pointless: I could not have said what it should achieve. That is the first problem.

`install` copies a source file to a destination, replacing whatever is there. The destination was `/dev/null`. On those two VMs, `/dev/null` stopped being the special device every Linux system relies on and became an ordinary file.

The next test run printed almost nothing. I had piped its output through a `grep` that dropped the `vagrant` and `Connection` noise, so an empty result looked like "no output" instead of "the command did not run". Checking the exit code showed `255`, and a raw `ssh -v` showed:

```text
kex_exchange_identification: read: Connection reset by peer
```

The server closed the connection before it even sent its banner.

## The trap: I had seen this symptom before

Earlier in the same project, SSH died after provisioning with exactly that message. The cause then was real and different: a partial package upgrade left an old OpenSSH running on new OpenSSL libraries. It took a long investigation to find, and it is fixed in `core/provision-base.sh` (OpenSSH is upgraded first).

Pattern-matching on that memory would have sent me hunting through package versions again. What actually helped was one question: **what did I change last?** The only change since the last working SSH session was that command.

The same symptom has more than one cause. A message names where it failed, not why.

## How I confirmed and fixed it

- **Fix:** reboot the two VMs. `/dev` is rebuilt at boot, so the device node came back. After the reboot, `ls -l /dev/null` showed `crw-rw-rw- 1 root root 1, 3`, the normal character device, and SSH worked.
- **What I did not prove:** I could not log in to look at the broken file, and I did not read the sshd logs. So "a regular file at `/dev/null` broke sshd" is an inference from the timeline and from the recovery. It is a strong one, but it is not a traced mechanism.
- **Cost:** about two minutes of VM reboots, plus a confusing test run. The cluster was disposable, so nothing was lost.

## Lessons

1. **Do not run a command you cannot explain.** If I cannot say what it should print or change, it does not belong in a test run. "Just checking" commands are still commands with effects.
2. **Know which tools overwrite their destination.** `install`, `cp`, `mv` and `>` all replace the target. Pointing any of them at a path under `/dev` is almost never right. Test paths with `ls -l` first; a leading `c` or `b` in the mode means a device.
3. **Do not filter away the evidence.** My `grep -v` made a failure look like silence. When a command prints nothing unexpectedly, look at the exit code and the unfiltered output before anything else.
4. **Ask "what changed last?" before "what does this look like?"** Recent change beats a remembered symptom.
5. **Disposable infrastructure is the safety net.** A lab you can reboot, reprovision or rebuild turns a serious mistake into a two-minute detour. This is also why the lab's reset steps (snapshots, `vagrant provision`) matter.
6. **Say what is inferred.** Report confirmed facts and likely causes separately.

## What this means for learners

Chapter 6 plants problems for you to solve. Real incidents often come from a well-meant command like the one above, not from hardware. As you troubleshoot:

- Write down every command you run and why. When something breaks, that list is your "what changed last".
- Read the exit code and the full error before you filter anything.
- When SSH is unreachable, you still have the VM console and a reboot. Know that route before you need it.

## An idea for the lab

A scenario where a core system path (such as `/dev/null`) has been damaged would teach this lesson well: the ticket would say "nobody can log in", and the fix would be to find the broken device node and recreate it. It is not implemented. If it is wanted, it would be added to the troubleshooting module under a new issue.
