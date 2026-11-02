# Admin guide

For the person who runs this lab for other people (an "admin"): how the planted problems work, how to hand them out, how to recover, how to run the Slurm chapter, and how to maintain the lab. Learners need only the [lab README](../README.md) and the module READMEs.

The cause and fix of every planted problem are in [SOLUTIONS.md](SOLUTIONS.md). That file is a spoiler for learners.

## 1. How the fault system works

`inject-fault` plants one practice problem on a node and gives the learner the user's ticket. `fault-status` (which calls `inject-fault --check`) tells the learner whether it is fixed.

| Item | Detail |
|---|---|
| Installed as | `/usr/local/bin/inject-fault` and `/usr/local/bin/fault-status` on every node (from [modules/02-troubleshooting/bin/](../modules/02-troubleshooting/bin/)) |
| Needs | root (`sudo`), and a node provisioned by `core/provision-base.sh` |
| State directory | `/var/lib/hpc-lab/fault/` (root only): `active` (scenario name), `ticket`, `solution`, `data/` (backups) |
| Limit | One active problem per node |
| Checks | Based on the end state of the system, not on the commands used |

Commands:

| Command | Purpose |
|---|---|
| `sudo inject-fault <scenario> --yes` | Plant a named problem |
| `sudo inject-fault random --yes` | Plant a random eligible problem (name hidden) |
| `sudo inject-fault random --seed N --yes` | Same, reproducible for a given `N` |
| `sudo inject-fault --ticket` | Show the ticket again (the state directory is root-only) |
| `sudo inject-fault --check` | Fixed? Exit 0 yes, 1 no, 2 none active |
| `sudo inject-fault --reveal` | Show the cause and the fix |
| `sudo inject-fault --revert` | Undo the problem and clear the state |
| `inject-fault --list` | List scenarios and where each can run |

`--yes` is required when there is no terminal (for example `vagrant ssh <node> -c "..."`).

### Running an exercise session

1. Make sure the lab is healthy: `lab-verify` on every node. Take a snapshot first (`vagrant snapshot save clean`).
2. Choose how problems are assigned (section 2).
3. Learners plant, investigate and report using [module 02](../modules/02-troubleshooting/README.md).
4. Debrief with the notes in [SOLUTIONS.md](SOLUTIONS.md). Ask each learner for the four-point note: what the user reported, what was checked in order, the root cause, the fix.
5. Learners run `sudo inject-fault --revert` before the next exercise.

### Reboots

State is stored on disk and survives a reboot, but some effects do not:

| Survives a reboot | Disappears at reboot |
|---|---|
| `service-stopped`, `service-failed`, `bad-permissions`, `ssh-keys`, `locked-user`, `hosts-entry`, `nfs-unmounted` | `disk-full` and `inode-exhaustion` (loop mounts), `runaway-process` (processes) |

After a reboot, a learner should run `sudo inject-fault --revert` to clear the state. Otherwise `fault-status` keeps reporting `NOT FIXED YET` for the problems that disappeared (for example a missing `/data/app` mount).

## 2. Assigning problems

| Approach | How | Use it when |
|---|---|---|
| Self-service | Learners run `sudo inject-fault random --yes` | Practice; each learner gets something different |
| Seeded | You give each learner a number: `sudo inject-fault random --seed N --yes` | You need a known problem per learner |
| Named | `sudo inject-fault <scenario> --yes` | You are demonstrating one scenario, or testing |

### Seed table

The scenario chosen by a seed depends on the node's role, because the eligible pool differs:

| Role | Eligible scenarios |
|---|---|
| `login` | all except `nfs-unmounted` |
| `compute` | all except `bad-permissions` and `ssh-keys` |

Seeds 1 to 12, computed with Rocky Linux 9.3's Bash 5.1.8 and the same selection code as `inject-fault` (two entries were also planted for real and matched):

| Seed | On `login` | On `compute` |
|---|---|---|
| 1 | `bad-permissions` | `nfs-unmounted` |
| 2 | `disk-full` | `hosts-entry` |
| 3 | `bad-permissions` | `locked-user` |
| 4 | `inode-exhaustion` | `locked-user` |
| 5 | `service-failed` | `service-stopped` |
| 6 | `inode-exhaustion` | `service-failed` |
| 7 | `service-failed` | `disk-full` |
| 8 | `service-stopped` | `service-stopped` |
| 9 | `service-stopped` | `locked-user` |
| 10 | `locked-user` | `runaway-process` |
| 11 | `runaway-process` | `nfs-unmounted` |
| 12 | `service-failed` | `nfs-unmounted` |

The mapping depends on the scenario list and on the Bash version of the image. If you change either, check a seed on a real node and regenerate the table:

```bash
sudo inject-fault random --seed 17 --yes
sudo inject-fault --reveal
sudo inject-fault --revert
```

## 3. Checking the scenarios yourself

What has been run on real nodes (Rocky Linux 9.3, one login node and two compute nodes, 2026-11-02):

| Check | Result |
|---|---|
| Plant, `fault-status`, `--ticket`, `--reveal` and `--revert` for all ten scenarios | Worked (nine on the login node, `nfs-unmounted` on a compute node); `lab-verify` stayed `HEALTHY` after each revert |
| The fix from the answer key, applied by hand, then `fault-status` says `FIXED` | Done for `hosts-entry`, `service-stopped`, `locked-user`, `runaway-process` and `nfs-unmounted` |
| One problem at a time per node; a scenario refused on the wrong role | Worked |
| Same seed gives the same problem | Worked |

Not yet run by hand to the `FIXED` state: `disk-full`, `inode-exhaustion`, `service-failed`, `bad-permissions` and `ssh-keys`. If you rely on them, run this once on your lab:

| Step | Expected |
|---|---|
| `sudo inject-fault <scenario> --yes` | Prints the ticket without errors |
| The diagnose commands in [SOLUTIONS.md](SOLUTIONS.md) | Show the problem |
| `fault-status` before the fix | `NOT FIXED YET` |
| Apply the fix from the answer key | `fault-status` says `FIXED` |
| `sudo inject-fault --revert` | `The node is back to normal`, and `lab-verify` passes |

Pay attention to `ssh-keys` (sshd and the NFS-hosted home directories), `disk-full` and `inode-exhaustion` (loop mounts), and `service-failed` (confirm the typo really stops `chronyd` on your image).

## 4. Recovery

| Situation | Action |
|---|---|
| Learner finished or gave up | `sudo inject-fault --revert` |
| Node rebooted during an exercise | `sudo inject-fault --revert`, then plant again if needed |
| `--revert` fails or the node is badly broken | `vagrant snapshot restore clean`, or `vagrant destroy -f` and `vagrant up` |
| SSH to a node is dead and `vagrant ssh` fails | Reboot the node from the hypervisor (for libvirt: `virsh -c qemu:///system reboot <domain>`); `/dev` and the runtime state are rebuilt at boot |
| A planted problem hit the wrong node | Run `sudo inject-fault --revert` on that node |

Tips:

- Take the snapshot before any exercise session.
- Do not run a scenario on a node that is being used for something else. Problems such as `runaway-process` and `service-failed` affect the whole node.

## 5. Adding a scenario

In [inject-fault.sh](../modules/02-troubleshooting/bin/inject-fault.sh), add the scenario name to `SCENARIOS` and define five functions, using underscores in place of hyphens in the names:

| Function | Purpose |
|---|---|
| `ticket_<name>` | Prints the user's complaint (symptom only) |
| `solution_<name>` | Prints the cause and the fix (shown by `--reveal`) |
| `inject_<name>` | Plants the problem. Back up anything it changes under `$DATA` |
| `check_<name>` | Returns 0 when the end state is fixed |
| `revert_<name>` | Restores the original state |

If the scenario only works on one role, add it to `eligible()` and `role_note()`. Then add an entry to [SOLUTIONS.md](SOLUTIONS.md), rebuild the seed table (the pool changed), and check the scenario as in section 3. Roll the updated script out with `vagrant provision --provision-with stage-clean,stage,stage-modules,base`.

## 6. The Slurm chapter

(To be completed with the Slurm 26 build steps.)

## 7. Support tools for your own use

These are installed on every node and are useful when a learner asks for help or when you triage a problem.

| Tool | Use it to |
|---|---|
| `node-health [node]` | See in one screen whether a node is healthy (Slurm state and reason, load, memory, swap, full disks and inodes, hung mounts, services, clock, GPUs) |
| `why-pending [jobid]` | Explain a pending job's reason code in plain words and see who has to act |
| `collect-evidence <user> [jobid]` | Capture the standard facts for a ticket in one file (use `--jira` for pasting) |
| `lab-verify`, `slurm-verify` | Check the lab base and the Slurm build |
| `inject-fault --reveal` | See which problem a learner was given |

`why-pending --codes` prints a glossary of the reason codes, which also works as a handout for chapter 8.

## 8. Maintaining the lab

**Never commit**

- Seed tables for an assessment, grading notes, and any other assessment material.
- Internal URLs, such as a link to your own hosted lab boxes. Set `LAB_BOX_URL` in the environment instead of committing it.
- Generated files: `lab-profile.json`, `lab-report-*.txt`, `evidence-*.txt`, `.vagrant/`, `*.box` (covered by `.gitignore`).

**Housekeeping**

- Scripts keep Unix line endings (`.gitattributes` enforces this on clone) and stay executable.
- After any change to a script, run `vagrant provision` on a test lab, rerun the checks in section 3, and add a line to the change log below.
- Keep [SOLUTIONS.md](SOLUTIONS.md) in step with the scenario functions in `inject-fault.sh`: the ticket, `check_*` and `solution_*` text are the source of truth.
- Learners who open an issue may attach a `python3 lab.py report` file. It includes the lab folder path, so tell them they can remove it.
- Internal names kept on purpose so existing labs keep working: `/etc/hpc-lab-release`, `# hpc-lab mount` and `# BEGIN hpc-lab` in system files, and `/var/lib/hpc-lab/fault`.

## 9. Change log

| Date | Change |
|---|---|
| 2026-11-03 | Imported into the repository: fault system, answer key (now [SOLUTIONS.md](SOLUTIONS.md)), seed table, recovery and maintenance notes. |
