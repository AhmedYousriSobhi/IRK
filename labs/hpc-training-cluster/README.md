# hpc-training-cluster

A small virtual cluster for learning HPC system administration by doing. You work through a sequence of chapters, from your first login to building Slurm, and practice troubleshooting on problems planted in the cluster. Nothing touches a real system.

> **Status:** being imported file by file ([#4](https://github.com/AhmedYousriSobhi/IRK/issues/4)). Only the structure and this overview exist so far. Links to modules and chapters are filled in as they land.

## Architecture

| Node | Role | IP | Resources |
|---|---|---|---|
| `login` | Login node, NFS server for `/shared` | 192.168.56.10 | 1 GB RAM, 1 vCPU |
| `compute1` | Compute node | 192.168.56.11 | 1 GB RAM, 1 vCPU |
| `compute2` | Compute node | 192.168.56.12 | 1 GB RAM, 1 vCPU |

- **OS:** Rocky Linux 9. Other RHEL 9 clones are accepted by the scripts but not tested.
- **Providers:** VirtualBox, libvirt, or QEMU, through Vagrant.
- **Host needs:** 8 GB RAM for the full lab (4 GB for a reduced 2-node lab), about 50 GB free disk, CPU virtualization enabled, Python 3.8+.

## How the lab is organized

One cluster, built from a small core plus modules. Each module is a folder that holds everything for one area: its own `README.md` with the chapters, its tools, and an optional provisioner.

```text
hpc-training-cluster/
├── README.md                 # this file: overview, module index, timeline
├── core/                     # base cluster setup and health check (always applied)
└── modules/
    ├── 01-sysadmin-foundations/
    ├── 02-troubleshooting/
    ├── 03-slurm/
    └── 04-health-monitoring/
```

The Vagrantfile, `lab.py` and the remaining lab files are added in later commits of the same PR.

## Modules

| Module | What you practice | Status |
|---|---|---|
| [01-sysadmin-foundations](modules/01-sysadmin-foundations/README.md) | Storage and NFS, time and services, users and SSH keys, permissions and processes, name resolution | Chapter text tracked in [#6](https://github.com/AhmedYousriSobhi/IRK/issues/6) |
| [02-troubleshooting](modules/02-troubleshooting/README.md) | Investigate planted faults from a user's ticket and write up the root cause | Planned |
| [03-slurm](modules/03-slurm/README.md) | Prepare, build and verify Slurm; understand why a job is pending | Planned |
| [04-health-monitoring](modules/04-health-monitoring/README.md) | Read a node's health at a glance | Planned |

## Chapter timeline

Self-paced. Each chapter assumes the earlier ones. Times are estimates.

| Chapter | Topic | Module | Est. time |
|---|---|---|---|
| 0 | Set up the lab, first login, health check, snapshot | core | 1-2 h |
| 1 | Storage and the shared filesystem | 01 | 1 h |
| 2 | Time sync and services | 01 | 1 h |
| 3 | Users, groups and SSH keys | 01 | 1.5 h |
| 4 | Permissions and processes | 01 | 1 h |
| 5 | Name resolution and hosts | 01 | 45 min |
| 6 | Troubleshooting practice | 02 | 2-3 h |
| 7 | Prepare and build Slurm | 03 | 3-4 h |
| 8 | Verify Slurm, read pending jobs, collect evidence | 03 | 1-2 h |
| 9 | Node health checks | 04 | 45 min |

## Security note

This is a disposable lab. It uses a well-known default password for the lab accounts, enables SSH password login, and (during the Slurm chapters) leaves a copy of the munge key on shared storage until it is cleaned up. Never reuse these settings or passwords on a real system, and do not expose the lab VMs to a network you do not control.
