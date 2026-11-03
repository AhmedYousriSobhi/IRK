# <lab-name>

<!-- Copy this folder to labs/<lab-name>/ (lowercase, hyphenated) and replace every <placeholder>. Delete the comments. -->

<One or two sentences: what this lab simulates and what you learn or test with it.>

## Architecture

| Node | Role | IP | Resources |
|---|---|---|---|
| `node1` | <role, for example login node> | 192.168.56.11 | 1 GB RAM, 1 vCPU |
| `node2` | <role, for example compute node> | 192.168.56.12 | 1 GB RAM, 1 vCPU |

- **OS:** <distribution and version>. Say which versions are tested.
- **Providers:** VirtualBox or libvirt, through Vagrant.
- **Host needs:** <RAM, free disk, virtualization>. Measure these; do not guess.

## Quick start

```bash
./up.sh                      # build the lab (or: vagrant up)
vagrant ssh node1            # log in
./down.sh                    # stop it, keeping the disks
./down.sh --destroy          # delete it completely
```

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `LAB_NODES` | `2` | Number of nodes (1 to 9) |
| `LAB_MEM_MB` | `1024` | RAM per node in MB |
| `LAB_CPUS` | `1` | vCPUs per node |
| `LAB_SUBNET` | `192.168.56` | First three octets of the private network |
| `LAB_VM_PREFIX` | `lab-` | Prefix of the VM and network names |
| `LAB_BOX` | `generic/rocky9` | Vagrant box |

## What you can do here

<The exercises, tests or experiments this lab supports. Link to each module or script if the lab is split up.>

## Reset

<How to get back to a clean state: a snapshot (`vagrant snapshot restore`), re-provisioning, or `./down.sh --destroy` and `./up.sh`.>

## Security note

<State anything insecure on purpose (default passwords, open services) and that the lab is disposable. Delete this section only if there is nothing to say.>

## Making the lab modular (optional)

When a lab has several topics, split it into a small `core/` plus `modules/NN-<name>/`, each module with its own `README.md`, an optional `bin/` of tools and an optional `provision.sh`. See [hpc-training-cluster](../hpc-training-cluster/README.md) for an example.
