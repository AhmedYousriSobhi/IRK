# hpc-training-cluster

A small virtual cluster for learning HPC system administration by doing. You work through a sequence of chapters, from your first login to building Slurm, and practice troubleshooting on problems planted in the cluster. Nothing touches a real system.

> **Status:** being imported file by file ([#4](https://github.com/AhmedYousriSobhi/IRK/issues/4)). Only the structure and this overview exist so far. Links to modules and chapters are filled in as they land.

## Architecture

| Node | Role | IP | Resources |
|---|---|---|---|
| `login` | Login node, NFS server for `/shared` | 192.168.56.10 | 512 MB RAM, 1 vCPU |
| `compute1` | Compute node | 192.168.56.11 | 512 MB RAM, 1 vCPU |
| `compute2` | Compute node | 192.168.56.12 | 512 MB RAM, 1 vCPU |

- **OS:** Rocky Linux 9. Other RHEL 9 clones are accepted by the scripts but not tested.
- **Providers:** VirtualBox, libvirt, or QEMU, through Vagrant.
- **Memory per node:** 512 MB by default, tested through the whole lab including Slurm. Raise it with `LAB_MEM_MB` (see Settings) if you install extra software or run memory-hungry jobs.
- **Host needs:** 8 GB RAM for the full lab (4 GB for a reduced 2-node lab), about 50 GB free disk, CPU virtualization enabled, Python 3.8+.

## Quick start (chapter 0)

Run these in this folder, on your computer (the host).

```bash
python3 lab.py check --save          # checks your computer; prints the exact vagrant command to run
vagrant up --provider=<provider>     # builds the nodes (login first); the first run downloads the box
vagrant ssh login                    # your first login
lab-verify                           # inside the VM: should end with "Result: HEALTHY"
```

Do the same on `compute1` and `compute2` (`vagrant ssh compute1`). A first build takes roughly 15 minutes, because every node downloads its packages.

To try only two nodes (login and one compute), which also needs less memory, set `LAB_COMPUTE=1` before `vagrant up`.

Useful commands:

| Command | What it does |
|---|---|
| `python3 lab.py modules` | Lists the modules and the tools each one installs |
| `vagrant status` | Shows which nodes are running |
| `vagrant halt` / `vagrant up` | Stops / starts the cluster; your work stays |
| `vagrant snapshot save clean` | Saves a restore point (restore: `vagrant snapshot restore clean`) |
| `vagrant destroy -f` | Deletes the cluster completely |

## Settings

Set them as environment variables before `vagrant up` (all optional). Example: `LAB_MEM_MB=1024 LAB_COMPUTE=1 vagrant up --provider=libvirt`.

| Variable | Default | Meaning |
|---|---|---|
| `LAB_MEM_MB` | `512` | RAM per node in MB |
| `LAB_LOGIN_MEM_MB` | same as `LAB_MEM_MB` | RAM for the login node only |
| `LAB_CPUS` | `1` | vCPUs per node |
| `LAB_COMPUTE` | `2` (`1` on a `reduced` profile) | Number of compute nodes (1 to 9) |
| `LAB_PASSWORD` | `hpclab` | Password of the lab accounts |
| `LAB_SUBNET` | `192.168.56` | First three octets of the private network |
| `LAB_VM_PREFIX` | `hpc-` | Prefix of the VM and network names. Change it together with `LAB_SUBNET` to run next to another lab |
| `LAB_PROFILE` | from `lab-profile.json` | `full`, `reduced` or `unsupported` |
| `LAB_BOX`, `LAB_BOX_URL` | `generic/rocky9` | Use another box or a local `.box` file if the default download fails |

If a node does not have enough room, the setting `LAB_MEM_MB` is the first one to change.

## How the lab is organized

One cluster, built from a small core plus modules. Each module is a folder that holds everything for one area: its own `README.md` with the chapters, its tools, and an optional provisioner.

```text
hpc-training-cluster/
├── README.md                 # this file: overview, module index, timeline
├── Vagrantfile               # describes the nodes
├── lab.py                    # checks your computer before you build
├── core/                     # base cluster setup and health check (always applied)
└── modules/
    ├── 01-sysadmin-foundations/
    ├── 02-troubleshooting/
    ├── 03-slurm/
    └── 04-health-monitoring/
```

## Modules

| Module | What you practice | Status |
|---|---|---|
| [01-sysadmin-foundations](modules/01-sysadmin-foundations/README.md) | Storage and NFS, time and services, users and SSH keys, permissions and processes, name resolution | Chapter text tracked in [#6](https://github.com/AhmedYousriSobhi/IRK/issues/6) |
| [02-troubleshooting](modules/02-troubleshooting/README.md) | Investigate planted faults from a user's ticket and write up the root cause | Tools imported and tested |
| [03-slurm](modules/03-slurm/README.md) | Prepare, build and verify Slurm; understand why a job is pending | Tools imported and tested |
| [04-health-monitoring](modules/04-health-monitoring/README.md) | Read a node's health at a glance | Tool imported and tested |

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
