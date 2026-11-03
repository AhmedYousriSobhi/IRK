# 04 - Health monitoring

Chapter 9. You read the health of a node on one screen: Slurm state, load, memory, swap, disks and inodes, mounts, services and clock.

Prerequisite: chapters 1 to 5, and chapter 7 if you want the Slurm lines ([03-slurm](../03-slurm/README.md)). Without Slurm the tool still works and says it has no Slurm view.

This module has no provisioner. Its tool is installed on every node by `vagrant up`.

## Tool

| Tool | What it does |
|---|---|
| `node-health` | Prints one tagged line per item and ends with a verdict. Read-only. |

```bash
node-health              # this node
node-health compute1     # another node
node-health --os-only    # only the operating-system view of this node
```

Each line is tagged `[ OK ]`, `[WARN]`, `[FAIL]` or `[INFO]`. The last line is `HEALTHY`, `ATTENTION` (warnings only) or `PROBLEM` (at least one failure). The exit code is 0 unless something failed. Run `node-health --help` for the list.

## What it checks

| View | Items |
|---|---|
| Slurm | node state and the reason it is drained or down, CPUs and memory allocated, GRES |
| Operating system | load per CPU, available memory, swap, full disks and inodes, network mounts that stop answering, services that should be running, clock sync, failed systemd units, GPUs if `nvidia-smi` exists |

Thresholds: load above 1 per CPU warns and above 2 fails; available memory under 10% warns and under 5% fails; disks and inodes warn at 90% and fail at 98%.

## Good to know

- **Another node:** the Slurm view always works. The operating-system view runs over SSH, so it needs passwordless SSH to that node (the keys from chapter 3). Without them, the tool says so and you run `node-health` on that node itself.
- **The Slurm view can lag.** It shows what the controller last heard. If `slurmd` just stopped, the node still shows `IDLE` until Slurm's timeout passes, while the operating-system view already shows `slurmd is enabled but not running`. Compare both views.
- **The login node is not a compute node.** `node-health login` says it is not known to Slurm. That is expected.
- **A hung NFS mount** (for example `login` stopped exporting `/shared`) is reported as a failure after 5 seconds, without blocking the tool.
- **Load average lags.** After a burst of work, the one-minute load stays high for a while.

## Try it

1. Run `node-health` on each node of a healthy cluster. Read every line.
2. Break something and run it again, then fix it and watch the verdict return: stop a service (`sudo systemctl stop chronyd`), drain a node (`sudo scontrol update NodeName=compute1 State=DRAIN Reason=test`), or start a few busy loops.
3. Combine it with chapter 6: plant a problem with `sudo inject-fault random`, then let `node-health` point you at the area before you dig in.

> **Status:** the tool is imported and tested. The written chapter text is not part of this module yet ([#6](https://github.com/AhmedYousriSobhi/IRK/issues/6)).
