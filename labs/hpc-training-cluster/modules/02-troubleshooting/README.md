# 02 - Troubleshooting

Chapter 6. A problem is planted on a node and you receive the user's ticket. You investigate with normal administration tools, fix the cause, and write up what you checked, the root cause and the fix.

Prerequisite: chapters 1 to 5 ([01-sysadmin-foundations](../01-sysadmin-foundations/README.md)). The problems use exactly those skills: storage, services, accounts, permissions, processes, SSH and name resolution.

## Tools

These are installed on every node by `vagrant up` (they live in this module's `bin/`).

| Tool | What it does |
|---|---|
| `inject-fault` | Plants a problem on the node you are logged in to, shows its ticket, checks whether it is fixed, and can undo it. |
| `fault-status` | The learner-facing check: "am I done?" It also reminds you what to write in your note. |
| `collect-evidence` | Gathers the standard facts for a support ticket into one text file (account, storage, node health, and later Slurm job details). Read-only. |

Run `inject-fault --help` or `collect-evidence --help` for every option.

## How an exercise runs

1. Log in to a node and plant a problem. The name stays hidden, so you investigate the way you would on the job:

   ```bash
   sudo inject-fault random
   ```

   The ticket is printed: the user's complaint, in the user's words.
2. Investigate with the tools from chapters 1 to 5. Change one thing at a time and note what you find.
3. Check yourself:

   ```bash
   fault-status          # exit code 0 = fixed, 1 = not yet, 2 = nothing planted
   sudo inject-fault --ticket     # read the ticket again
   ```
4. When `fault-status` says `FIXED`, write your note: what the user reported, what you checked in order, the root cause, and what you changed.
5. Gather evidence for the ticket if you want to practice that too: `collect-evidence alice` (add `--jira` for Jira formatting).

Stuck? `sudo inject-fault --reveal` shows what was planted and how to fix it. Try everything else first; that is where the learning is.

To start over, run `sudo inject-fault --revert`. It undoes the problem and restores the node.

## Good to know

- Only one problem is active on a node at a time.
- Some problems only make sense on one kind of node (for example, one needs the login node and one needs a compute node). `inject-fault random` picks one that fits the node you are on.
- Problems about disk space, inodes and processes disappear at reboot. The others persist until you fix or revert them.
- `inject-fault random --seed N` plants the same problem for the same number, so a group can work on the same exercise or an admin can give each learner a different one.
- `inject-fault --list` shows every scenario by name. That reveals the causes, so use it only after you have finished.
- The tools refuse to run on anything that is not a provisioned lab node.

## Check the cluster afterwards

`lab-verify` (from the core) should report `HEALTHY` again once the problem is fixed or reverted.

> **Status:** the tools are imported and tested. The written chapter text for chapter 6 is not part of this module yet, and the admin-side solutions are tracked in [#5](https://github.com/AhmedYousriSobhi/IRK/issues/5).
