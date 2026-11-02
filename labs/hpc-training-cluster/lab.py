#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lab.py - preflight checks for the HPC training cluster (Vagrant + VirtualBox, libvirt or QEMU)

Runs on Windows, macOS and Linux using only the Python standard library.
It detects the operating system it is running on and applies the matching checks.

Usage (from the lab folder):
    python lab.py check                  run all checks
    python lab.py check --save           also write lab-profile.json for the Vagrantfile
    python lab.py check --fix-eol        convert Windows line endings in lab scripts to LF
    python lab.py check --json           machine-readable output
    python lab.py check --provider qemu  force a provider (auto | virtualbox | libvirt | qemu)
    python lab.py report --name NAME     run the checks and write a report file to attach when asking for help
    python lab.py modules                list the lab modules, their tools and their provisioners

On Windows use "py lab.py check" if "python" is not found.
Exit code: 0 = ready (possibly with warnings), 1 = not ready, 2 = usage problem.
"""
from __future__ import print_function

import argparse
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import textwrap
import urllib.error
import urllib.request
from datetime import datetime

if sys.version_info < (3, 8):
    sys.stderr.write("lab.py needs Python 3.8 or newer (you have %s).\n" % platform.python_version())
    sys.exit(2)

TOOL_VERSION = "0.2.0"
GIB = 1024 ** 3

# ---- thresholds (edit here if the lab sizing changes) ----------------------
MIN_RAM_FULL_GIB = 5       # 3 VMs x 512 MB use ~1.5 GB of host RAM (measured); the rest is for the host system
MIN_RAM_REDUCED_GIB = 3.5  # 4 GB laptops: reduced lab (login + 1 compute, ~1 GB of host RAM)
MIN_CORES_OK = 4
MIN_CORES_FAIL = 2
DISK_OK_GIB = 50
DISK_FAIL_GIB = 30
VBOX_MIN_X86 = (7, 0)
VBOX_MIN_ARM = (7, 1)      # first VirtualBox release that runs on Apple Silicon
VAGRANT_MIN = (2, 3)
QEMU_MIN = (7, 0)
# Order tried when --provider auto. Maintainers: flip this after the Apple Silicon pilot if needed.
PROVIDER_PREFERENCE = ["virtualbox", "libvirt", "qemu"]  # libvirt is Linux only
# Maintainers: add the host that serves the lab boxes here (checked for reachability).
NETWORK_TARGETS = ["https://www.virtualbox.org", "https://releases.hashicorp.com"]

DEFAULT_BOX = "generic/rocky9"  # keep in sync with BOX in the Vagrantfile

PASS, WARN, FAIL, INFO = "PASS", "WARN", "FAIL", "INFO"
COLORS = {PASS: "32", WARN: "33", FAIL: "31", INFO: "36"}


class Result(object):
    def __init__(self, status, name, detail="", hint="", blocking=False):
        self.status = status
        self.name = name
        self.detail = detail
        self.hint = hint
        self.blocking = blocking  # this machine cannot run the lab locally

    def as_dict(self):
        return {"status": self.status, "name": self.name, "detail": self.detail,
                "hint": self.hint, "blocking": self.blocking}


# ---- helpers ---------------------------------------------------------------
def run(cmd, timeout=15, cwd=None):
    """Run a command without a shell. Returns (returncode or None, output)."""
    kwargs = {}
    if os.name == "nt":
        kwargs["creationflags"] = 0x08000000  # CREATE_NO_WINDOW
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout, universal_newlines=True, errors="replace",
                           cwd=cwd, **kwargs)
        return p.returncode, (p.stdout or "").strip()
    except FileNotFoundError:
        return None, ""
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except Exception as exc:  # pragma: no cover - defensive
        return None, str(exc)


def find_tool(name, extra_paths):
    found = shutil.which(name)
    if found:
        return found
    for candidate in extra_paths:
        if candidate and os.path.isfile(candidate):
            return candidate
    return None


def parse_version(text):
    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text or "")
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))


def fmt_version(ver):
    return ".".join(str(x) for x in ver) if ver else "unknown"


def install_hint(tool, os_name):
    urls = {"virtualbox": "https://www.virtualbox.org/wiki/Downloads",
            "vagrant": "https://developer.hashicorp.com/vagrant/install",
            "qemu": "https://www.qemu.org/download/"}
    cmds = {
        ("windows", "virtualbox"): "winget install Oracle.VirtualBox",
        ("windows", "vagrant"): "winget install Hashicorp.Vagrant",
        ("macos", "virtualbox"): "brew install --cask virtualbox",
        ("macos", "vagrant"): "brew install --cask vagrant",
        ("windows", "qemu"): "winget install SoftwareFreedomConservancy.QEMU",
        ("macos", "qemu"): "brew install qemu",
    }
    if (os_name, tool) == ("linux", "qemu"):
        return "Install qemu-system for your CPU with your package manager (see " + urls[tool] + ")"
    hint = "Download: " + urls[tool]
    if (os_name, tool) in cmds:
        hint += " (or, if you use a package manager: " + cmds[(os_name, tool)] + ")"
    return hint


# ---- environment detection -------------------------------------------------
def detect_env():
    system = platform.system()
    if system == "Darwin":
        os_name = "macos"
    elif system == "Linux":
        os_name = "linux"
    elif system.startswith(("Windows", "MSYS", "CYGWIN", "MINGW")):
        os_name = "windows"
    else:
        os_name = system.lower() or "unknown"

    machine = platform.machine().lower()
    if machine in ("arm64", "aarch64"):
        arch = "aarch64"
    elif machine in ("x86_64", "amd64"):
        arch = "x86_64"
    else:
        arch = machine or "unknown"

    rosetta = False
    if os_name == "macos":
        # Reports 1 on Apple Silicon even when Python itself is an Intel build under Rosetta.
        rc, out = run(["sysctl", "-n", "hw.optional.arm64"])
        if rc == 0 and out.strip() == "1":
            rosetta = arch != "aarch64"
            arch = "aarch64"
    if os_name == "windows":
        ident = os.environ.get("PROCESSOR_IDENTIFIER", "").upper()
        if "ARM" in ident:
            arch = "aarch64"

    wsl = os_name == "linux" and "microsoft" in platform.release().lower()
    return {"os": os_name, "arch": arch, "rosetta": rosetta, "wsl": wsl,
            "platform": platform.platform(terse=True)}


# ---- hardware probes -------------------------------------------------------
def total_ram_bytes(os_name):
    if os_name == "linux":
        with open("/proc/meminfo") as fh:
            for line in fh:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) * 1024
    elif os_name == "macos":
        rc, out = run(["sysctl", "-n", "hw.memsize"])
        if rc == 0 and out.strip().isdigit():
            return int(out.strip())
    elif os_name == "windows":
        import ctypes

        class MEMORYSTATUSEX(ctypes.Structure):
            _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                        ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                        ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                        ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                        ("sullAvailExtendedVirtual", ctypes.c_ulonglong)]

        stat = MEMORYSTATUSEX()
        stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
            return int(stat.ullTotalPhys)
    return None


def windows_virt_info():
    """Ask PowerShell for hypervisor / firmware virtualization state (Windows only)."""
    script = ("$c = Get-CimInstance Win32_ComputerSystem; "
              "$p = Get-CimInstance Win32_Processor | Select-Object -First 1; "
              "'HYPERVISOR=' + $c.HypervisorPresent; "
              "'VTFW=' + $p.VirtualizationFirmwareEnabled")
    for shell in ("powershell", "pwsh"):
        rc, out = run([shell, "-NoProfile", "-NonInteractive", "-Command", script], timeout=40)
        if rc == 0 and "=" in out:
            info = {}
            for line in out.splitlines():
                if "=" in line:
                    key, _, val = line.partition("=")
                    info[key.strip()] = val.strip().lower()
            return info
    return {}


def interpret_windows_virt(info):
    """Pure function (easy to test): returns (status, detail, hyperv_active)."""
    hyp = info.get("HYPERVISOR") == "true"
    fw = info.get("VTFW")
    if hyp:
        return PASS, "enabled (a Windows hypervisor is already running)", True
    if fw == "true":
        return PASS, "enabled in firmware", False
    if fw == "false":
        return FAIL, "disabled in firmware (BIOS/UEFI)", False
    return WARN, "could not be determined", False


# ---- individual checks -----------------------------------------------------
def check_python(ctx):
    return Result(PASS, "Python", platform.python_version())


def check_platform(ctx):
    env = ctx["env"]
    detail = "%s, %s" % (env["platform"], env["arch"])
    if env["wsl"]:
        return Result(FAIL, "Operating system", detail + " (inside WSL)",
                      "Run this from Windows PowerShell or Command Prompt, not the WSL terminal: "
                      "py lab.py check. VirtualBox runs on Windows, not inside WSL.")
    if env["os"] not in ("windows", "macos", "linux"):
        return Result(FAIL, "Operating system", detail, "Unsupported host. Use a Windows, macOS or Linux machine, or a cloud VM.",
                      blocking=True)
    if env["os"] == "windows" and env["arch"] == "aarch64":
        return Result(FAIL, "Operating system", detail,
                      "Windows on ARM is not supported for the local lab. Use another machine or a cloud VM.",
                      blocking=True)
    if env["os"] == "linux" and env["arch"] != "x86_64":
        return Result(WARN, "Operating system", detail,
                      "Only x86_64 Linux hosts are tested; other CPU types may not work.",
                      blocking=True)
    if env["rosetta"]:
        return Result(WARN, "Operating system", detail + " (Python is running under Rosetta)",
                      "Your Mac is Apple Silicon. Install the native arm64 Python from python.org so tools "
                      "detect the right CPU. The lab needs the aarch64 box.")
    return Result(PASS, "Operating system", detail + " -> lab box: " + env["arch"])


def check_cpu(ctx):
    cores = os.cpu_count() or 0
    detail = "%d logical CPUs" % cores
    if cores >= MIN_CORES_OK:
        return Result(PASS, "CPU", detail)
    if cores >= MIN_CORES_FAIL:
        return Result(WARN, "CPU", detail + " (4+ recommended)", "The lab will be slow; use the reduced lab.")
    return Result(FAIL, "CPU", detail, "Too few CPUs for the local lab. Use another machine or a cloud VM.",
                  blocking=True)


def check_ram(ctx):
    total = total_ram_bytes(ctx["env"]["os"])
    if total is None:
        return Result(WARN, "Memory", "could not be read", "Check how much RAM your computer has: the full lab needs %g GiB, the reduced lab %g GiB." % (MIN_RAM_FULL_GIB, MIN_RAM_REDUCED_GIB))
    gib = total / float(GIB)
    ctx["ram_gib"] = round(gib, 1)
    detail = "%.1f GiB" % gib
    if gib >= MIN_RAM_FULL_GIB:
        return Result(PASS, "Memory", detail + " (full lab: 3 VMs)")
    if gib >= MIN_RAM_REDUCED_GIB:
        return Result(WARN, "Memory", detail + " (reduced lab: 2 VMs)",
                      "Close other heavy apps during labs. You will use the reduced 2-VM lab.")
    return Result(FAIL, "Memory", detail, "Not enough RAM for the local lab. Use another machine or a cloud VM.",
                  blocking=True)


def check_disk(ctx):
    try:
        free = shutil.disk_usage(ctx["path"] if os.path.isdir(ctx["path"]) else os.getcwd()).free / float(GIB)
    except Exception as exc:
        return Result(WARN, "Free disk", "could not be read (%s)" % exc)
    detail = "%.0f GiB free" % free
    if free >= DISK_OK_GIB:
        return Result(PASS, "Free disk", detail)
    if free >= DISK_FAIL_GIB:
        return Result(WARN, "Free disk", detail + " (50+ recommended)", "Free some space before downloading boxes.")
    return Result(FAIL, "Free disk", detail, "Free at least 30 GiB (50 recommended) on this drive.")


def check_path(ctx):
    p = ctx["path"]
    problems = []
    if " " in p:
        problems.append("contains spaces")
    if any(ord(c) > 127 for c in p):
        problems.append("contains non-ASCII characters")
    if ctx["env"]["os"] == "windows":
        if "onedrive" in p.lower():
            problems.append("is inside OneDrive (sync can corrupt VM files)")
        if p.startswith("\\\\"):
            problems.append("is a network path")
        if len(p) > 60:
            problems.append("is long")
    if not problems:
        return Result(PASS, "Lab folder", p)
    suggestion = "C:\\hpc-training-cluster" if ctx["env"]["os"] == "windows" else "~/hpc-training-cluster"
    return Result(WARN, "Lab folder", "%s %s" % (p, "; ".join(problems)),
                  "Move the lab folder to a short path such as %s." % suggestion)


def check_virtualization(ctx):
    env = ctx["env"]
    os_name = env["os"]
    bios_hint = ("Restart, open BIOS/UEFI setup (often F2, F10, Del or Esc) and enable Intel VT-x or AMD-V "
                 "(SVM Mode). If the setting is locked on a managed laptop, use another machine or a cloud VM.")
    if os_name == "linux":
        try:
            with open("/proc/cpuinfo") as fh:
                flags = set()
                for line in fh:
                    if line.startswith("flags"):
                        flags = set(line.split(":", 1)[1].split())
                        break
        except Exception:
            return Result(WARN, "Virtualization", "could not be determined")
        if "vmx" in flags or "svm" in flags:
            return Result(PASS, "Virtualization", "CPU virtualization available (%s)" % ("VT-x" if "vmx" in flags else "AMD-V"))
        if "hypervisor" in flags:
            return Result(FAIL, "Virtualization", "this machine is itself a virtual machine without nested virtualization",
                          "Enable nested virtualization on the host, or use another machine or a cloud VM.")
        return Result(FAIL, "Virtualization", "VT-x/AMD-V not available or disabled", bios_hint)
    if os_name == "macos":
        if env["arch"] == "aarch64":
            return Result(PASS, "Virtualization", "Apple Silicon (no BIOS setting needed)")
        rc, out = run(["sysctl", "-n", "machdep.cpu.features"])
        rc2, out2 = run(["sysctl", "-n", "kern.hv_support"])
        if (rc == 0 and "VMX" in out.upper().split()) or (rc2 == 0 and out2.strip() == "1"):
            return Result(PASS, "Virtualization", "Intel VT-x available")
        return Result(FAIL, "Virtualization", "not available", "This Mac does not expose hardware virtualization.")
    if os_name == "windows":
        info = ctx.setdefault("win_virt", windows_virt_info())
        status, detail, hyperv = interpret_windows_virt(info)
        ctx["hyperv_active"] = hyperv
        hint = bios_hint if status == FAIL else ("Run PowerShell and try again." if status == WARN else "")
        return Result(status, "Virtualization", detail, hint)
    return None


def check_windows_hypervisor(ctx):
    if ctx["env"]["os"] != "windows" or ctx.get("provider") == "qemu":
        return None  # QEMU uses the Windows hypervisor (WHPX), so it is not a conflict there
    if not ctx.get("hyperv_active"):
        return Result(PASS, "Windows hypervisor", "not active (VirtualBox runs at full speed)")
    extras = []
    if shutil.which("wsl"):
        extras.append("WSL present")
    if shutil.which("docker"):
        extras.append("Docker present")
    detail = "Hyper-V platform is active" + (" (%s)" % ", ".join(extras) if extras else "")
    return Result(WARN, "Windows hypervisor", detail,
                  "VirtualBox can run next to Hyper-V/WSL2 but may be slow or fail to start VMs. If that happens, "
                  "turn off 'Virtual Machine Platform', 'Windows Hypervisor Platform' and Hyper-V under 'Turn Windows "
                  "features on or off', disable Memory Integrity, and reboot. This also pauses WSL2 and Docker Desktop. "
                  "Only do this if you do not need WSL2 or Docker Desktop right now.")


def _virtualbox_tool(ctx):
    os_name = ctx["env"]["os"]
    pf = os.environ.get("ProgramFiles", r"C:\Program Files")
    extras = {
        "windows": [os.path.join(pf, "Oracle", "VirtualBox", "VBoxManage.exe")],
        "macos": ["/usr/local/bin/VBoxManage", "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"],
        "linux": ["/usr/bin/VBoxManage", "/usr/local/bin/VBoxManage"],
    }.get(os_name, [])
    path = find_tool("VBoxManage", extras)
    arm = ctx["env"]["arch"] == "aarch64"
    if not path:
        hint = install_hint("virtualbox", os_name)
        if os_name == "macos" and arm:
            hint += ". On Apple Silicon you need VirtualBox 7.1 or newer."
        return Result(FAIL, "VirtualBox", "not installed", hint)
    ctx["vbox_path"] = path
    rc, out = run([path, "--version"])
    ver = parse_version(out)
    if ver is None:
        return Result(WARN, "VirtualBox", "found at %s but the version could not be read" % path)
    ctx["vbox_version"] = fmt_version(ver)
    minimum = VBOX_MIN_ARM if arm else VBOX_MIN_X86
    if ver[:2] < minimum:
        return Result(FAIL if arm else WARN, "VirtualBox", "version %s is too old" % fmt_version(ver),
                      "Update VirtualBox to %d.%d or newer. %s" % (minimum[0], minimum[1], install_hint("virtualbox", os_name)))
    note = " (ARM64 guests only)" if arm else ""
    return Result(PASS, "VirtualBox", "version %s%s" % (fmt_version(ver), note))


def _virtualbox_driver(ctx):
    if ctx["env"]["os"] != "linux" or "vbox_path" not in ctx:
        return None
    if os.path.exists("/dev/vboxdrv"):
        return Result(PASS, "VirtualBox driver", "kernel module loaded")
    hint = "Load the module (sudo modprobe vboxdrv) or re-run the VirtualBox kernel setup (sudo /sbin/vboxconfig)."
    rc, out = run(["mokutil", "--sb-state"])
    if rc == 0 and "enabled" in out.lower():
        hint += " Secure Boot is enabled and may block the module; enroll the VirtualBox key, or disable Secure Boot."
    return Result(FAIL, "VirtualBox driver", "kernel module not loaded", hint)


def probe_virtualbox(ctx):
    results = [_virtualbox_tool(ctx)]
    driver = _virtualbox_driver(ctx)
    if driver:
        results.append(driver)
    return results


def vagrant_plugins(ctx):
    if "vagrant_plugins" not in ctx:
        ctx["vagrant_plugins"] = None
        if ctx.get("vagrant_path"):
            rc, out = run([ctx["vagrant_path"], "plugin", "list"], timeout=60)
            if rc == 0:
                ctx["vagrant_plugins"] = out
    return ctx["vagrant_plugins"]


def _qemu_tool(ctx):
    os_name, arch = ctx["env"]["os"], ctx["env"]["arch"]
    exe = "qemu-system-aarch64" if arch == "aarch64" else "qemu-system-x86_64"
    pf = os.environ.get("ProgramFiles", r"C:\Program Files")
    extras = {
        "windows": [os.path.join(pf, "qemu", exe + ".exe")],
        "macos": ["/opt/homebrew/bin/" + exe, "/usr/local/bin/" + exe],
        "linux": ["/usr/bin/" + exe, "/usr/local/bin/" + exe],
    }.get(os_name, [])
    path = find_tool(exe, extras)
    if not path:
        return Result(FAIL, "QEMU", "%s not installed" % exe, install_hint("qemu", os_name))
    ctx["qemu_path"] = path
    rc, out = run([path, "--version"])
    ver = parse_version(out)
    if ver is None:
        return Result(WARN, "QEMU", "found at %s but the version could not be read" % path)
    ctx["qemu_version"] = fmt_version(ver)
    if ver[:2] < QEMU_MIN:
        return Result(WARN, "QEMU", "version %s is old (%s)" % (fmt_version(ver), exe),
                      "Update QEMU to %d.%d or newer. %s" % (QEMU_MIN[0], QEMU_MIN[1], install_hint("qemu", os_name)))
    return Result(PASS, "QEMU", "version %s (%s)" % (fmt_version(ver), exe))


def _qemu_accel(ctx):
    path = ctx.get("qemu_path")
    if not path:
        return None
    os_name = ctx["env"]["os"]
    rc, out = run([path, "-accel", "help"])
    if rc != 0:
        return Result(WARN, "QEMU acceleration", "could not be determined",
                      "Run: %s -accel help and include the output when you ask for help." % os.path.basename(path))
    accels = set(re.findall(r"[a-z]+", out.lower()))
    if os_name == "linux":
        if "kvm" not in accels:
            return Result(FAIL, "QEMU acceleration", "this QEMU build has no KVM support",
                          "Install your distribution's qemu-kvm / qemu-system package.")
        if not os.path.exists("/dev/kvm"):
            return Result(FAIL, "QEMU acceleration", "/dev/kvm is missing",
                          "Enable VT-x/AMD-V in BIOS and load the module (sudo modprobe kvm_intel or kvm_amd).")
        if not os.access("/dev/kvm", os.R_OK | os.W_OK):
            return Result(FAIL, "QEMU acceleration", "no permission to use /dev/kvm",
                          "Add yourself to the kvm group: sudo usermod -aG kvm $USER, then log out and in.")
        return Result(PASS, "QEMU acceleration", "KVM available")
    if os_name == "macos":
        if "hvf" in accels:
            return Result(PASS, "QEMU acceleration", "HVF available")
        return Result(FAIL, "QEMU acceleration", "this QEMU build has no HVF support", "Reinstall QEMU (brew install qemu).")
    if os_name == "windows":
        if "whpx" not in accels:
            return Result(FAIL, "QEMU acceleration", "this QEMU build has no WHPX support", install_hint("qemu", os_name))
        if not ctx.get("hyperv_active"):
            return Result(FAIL, "QEMU acceleration", "Windows Hypervisor Platform is not enabled",
                          "Turn on 'Windows Hypervisor Platform' under 'Turn Windows features on or off', then reboot.")
        return Result(PASS, "QEMU acceleration", "WHPX available")
    return None


def _qemu_plugin(ctx):
    if not ctx.get("vagrant_path"):
        return Result(INFO, "vagrant-qemu plugin", "cannot be checked until Vagrant is installed")
    plugins = vagrant_plugins(ctx)
    if plugins is None:
        return Result(WARN, "vagrant-qemu plugin", "could not list Vagrant plugins")
    if "vagrant-qemu" in plugins:
        return Result(PASS, "vagrant-qemu plugin", "installed")
    return Result(FAIL, "vagrant-qemu plugin", "not installed", "Run: vagrant plugin install vagrant-qemu")


def probe_qemu(ctx):
    results = [_qemu_tool(ctx)]
    for fn in (_qemu_accel, _qemu_plugin):
        r = fn(ctx)
        if r:
            results.append(r)
    return results


def probe_libvirt(ctx):
    """libvirt (QEMU/KVM) via the vagrant-libvirt plugin. Linux hosts only."""
    if ctx["env"]["os"] != "linux":
        return None
    results = []
    virsh = shutil.which("virsh")
    if not virsh:
        results.append(Result(FAIL, "libvirt", "virsh not installed",
                              "Install libvirt and QEMU/KVM with your package manager "
                              "(for example libvirt-daemon-system + qemu-system on Debian/Ubuntu, "
                              "libvirt + qemu-kvm on RHEL/Fedora)."))
    else:
        ctx["virsh_path"] = virsh
        rc, out = run([virsh, "--version"])
        ver = parse_version(out)
        ctx["libvirt_version"] = fmt_version(ver)
        results.append(Result(PASS, "libvirt", "version %s" % ctx["libvirt_version"]))
        rc, out = run([virsh, "-c", "qemu:///system", "list", "--all"], timeout=20)
        if rc == 0:
            results.append(Result(PASS, "libvirt connection", "qemu:///system reachable"))
            rc2, out2 = run([virsh, "-c", "qemu:///system", "pool-list", "--all", "--name"], timeout=20)
            if rc2 == 0 and "default" not in out2.split():
                results.append(Result(WARN, "libvirt storage pool", "no storage pool named 'default'",
                                      "vagrant-libvirt uses the 'default' pool unless the Vagrantfile sets "
                                      "storage_pool_name. Define one, for example: virsh pool-define-as default "
                                      "dir --target /var/lib/libvirt/images, then pool-start and pool-autostart it."))
        else:
            last = (out.splitlines() or ["no output"])[-1][:80]
            results.append(Result(FAIL, "libvirt connection", "cannot connect to qemu:///system (%s)" % last,
                                  "Start the service (sudo systemctl enable --now libvirtd, or virtqemud.socket on "
                                  "newer distributions) and add yourself to the libvirt group: "
                                  "sudo usermod -aG libvirt $USER, then log out and back in."))
    if os.path.exists("/dev/kvm"):
        results.append(Result(PASS, "KVM", "/dev/kvm present"))
    else:
        results.append(Result(FAIL, "KVM", "/dev/kvm is missing",
                              "Enable VT-x/AMD-V in BIOS and load the module (sudo modprobe kvm_intel or kvm_amd)."))
    if not ctx.get("vagrant_path"):
        results.append(Result(INFO, "vagrant-libvirt plugin", "cannot be checked until Vagrant is installed"))
    else:
        plugins = vagrant_plugins(ctx)
        if plugins is None:
            results.append(Result(WARN, "vagrant-libvirt plugin", "could not list Vagrant plugins"))
        elif "vagrant-libvirt" in plugins:
            results.append(Result(PASS, "vagrant-libvirt plugin", "installed"))
        else:
            results.append(Result(FAIL, "vagrant-libvirt plugin", "not installed",
                                  "Run: vagrant plugin install vagrant-libvirt (it builds native code, so install "
                                  "the libvirt development headers first: libvirt-dev or libvirt-devel), or use "
                                  "your distribution's vagrant-libvirt package."))
    return results


def check_providers(ctx):
    """Probe VirtualBox and QEMU, pick one, and only complain about the one that will be used."""
    forced = ctx.get("provider_arg", "auto")
    probes = {"virtualbox": probe_virtualbox(ctx), "libvirt": probe_libvirt(ctx), "qemu": probe_qemu(ctx)}
    probes = {name: rs for name, rs in probes.items() if rs is not None}
    usable = {name: not any(r.status == FAIL for r in rs) for name, rs in probes.items()}
    candidates = PROVIDER_PREFERENCE if forced == "auto" else [forced]
    chosen = next((p for p in candidates if usable.get(p)), None)
    ctx["provider"] = chosen
    out = []
    for name, rs in probes.items():
        for r in rs:
            if chosen and name != chosen and r.status in (WARN, FAIL):
                r = Result(INFO, r.name, r.detail + " (not used)")
            out.append(r)
    if chosen:
        others = [n for n in probes if n != chosen and usable[n]]
        detail = chosen + (" (also usable: %s)" % ", ".join(others) if others else "")
        if forced != "auto":
            detail += " [forced with --provider]"
        out.append(Result(PASS, "Provider", detail))
        if chosen == "qemu":
            out.append(Result(WARN, "QEMU networking", "VM-to-VM private network is not verified by this check",
                              "The QEMU provider gives each VM its own NAT network by default. The cluster needs "
                              "VM-to-VM networking (extra setup such as the plugin's advanced networking or "
                              "socket_vmnet on macOS). Set up VM-to-VM networking for the QEMU provider before starting the lab."))
    else:
        if forced != "auto":
            hint = "The provider you forced (%s) is not usable. Fix its FAIL items or run without --provider." % forced
        else:
            hint = ("Install VirtualBox (simplest), or on Linux libvirt plus the vagrant-libvirt plugin, "
                    "or QEMU plus the vagrant-qemu plugin. See the FAIL items above for what is missing.")
        out.append(Result(FAIL, "Provider", "no usable virtualization provider", hint))
    return out


def check_vagrant(ctx):
    os_name = ctx["env"]["os"]
    extras = {
        "windows": [r"C:\HashiCorp\Vagrant\bin\vagrant.exe"],
        "macos": ["/opt/vagrant/bin/vagrant", "/usr/local/bin/vagrant"],
        "linux": ["/usr/bin/vagrant", "/usr/local/bin/vagrant"],
    }.get(os_name, [])
    path = find_tool("vagrant", extras)
    if not path:
        return Result(FAIL, "Vagrant", "not installed", install_hint("vagrant", os_name))
    ctx["vagrant_path"] = path
    rc, out = run([path, "--version"])
    ver = parse_version(out)
    if ver is None:
        return Result(WARN, "Vagrant", "found at %s but the version could not be read" % path)
    ctx["vagrant_version"] = fmt_version(ver)
    if ver[:2] < VAGRANT_MIN:
        return Result(WARN, "Vagrant", "version %s is old" % fmt_version(ver),
                      "Update Vagrant to %d.%d or newer. %s" % (VAGRANT_MIN[0], VAGRANT_MIN[1], install_hint("vagrant", os_name)))
    return Result(PASS, "Vagrant", "version %s" % fmt_version(ver))


def check_network(ctx):
    ok, bad = [], []
    for url in NETWORK_TARGETS:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "lab.py/" + TOOL_VERSION})
            urllib.request.urlopen(req, timeout=6).close()
            ok.append(url)
        except urllib.error.HTTPError:
            ok.append(url)  # the server answered, so it is reachable
        except Exception as exc:
            reason = getattr(exc, "reason", exc)
            bad.append("%s (%s)" % (url, str(reason)[:60]))
    if not bad:
        return Result(PASS, "Network", "%d/%d download hosts reachable" % (len(ok), len(NETWORK_TARGETS)))
    return Result(WARN, "Network", "unreachable: " + "; ".join(bad),
                  "Check your internet connection. Behind a proxy, set HTTPS_PROXY before running. "
                  "On a restricted network, download the box file elsewhere and set LAB_BOX_URL to its path.")


def _box_downloaded(ctx, box):
    """True if `vagrant box list` already has this box for the chosen provider."""
    vagrant = ctx.get("vagrant_path")
    if not vagrant:
        return False
    rc, out = run([vagrant, "box", "list"])
    if rc != 0:
        return False
    provider = ctx.get("provider")
    for line in out.splitlines():
        parts = line.split(None, 1)
        if parts and parts[0] == box and (not provider or "(%s," % provider in line):
            return True
    return False


def check_box(ctx):
    """Say whether the box is downloaded; if LAB_BOX_URL is set, confirm the file is really there."""
    url = os.environ.get("LAB_BOX_URL", "").strip()
    if not url:
        box = os.environ.get("LAB_BOX") or DEFAULT_BOX
        if _box_downloaded(ctx, box):
            return Result(PASS, "Lab box", "'%s' is already downloaded" % box)
        return Result(INFO, "Lab box", "'%s' is not downloaded yet; the first 'vagrant up' fetches it from "
                      "Vagrant Cloud (roughly 1 GB)" % box)
    if os.path.isfile(url):
        return Result(PASS, "Lab box file", "%s (%.0f MiB)" % (url, os.path.getsize(url) / 1024.0 ** 2))
    hint_404 = ("The box file is not at that address. Distributions move older releases (for example Rocky "
                "uses /vault/ for past minor versions). Fix LAB_BOX_URL, or download the .box file and run: "
                "vagrant box add <name> <file>.box")

    def probe(method, extra=None):
        headers = {"User-Agent": "lab.py/" + TOOL_VERSION}
        headers.update(extra or {})
        resp = urllib.request.urlopen(urllib.request.Request(url, method=method, headers=headers), timeout=15)
        size = resp.headers.get("Content-Length")
        resp.close()
        return size

    try:
        try:
            size = probe("HEAD")
        except urllib.error.HTTPError as exc:
            if exc.code not in (403, 405, 501):
                raise
            size = probe("GET", {"Range": "bytes=0-0"})  # some servers refuse HEAD
        extra = " (%.0f MiB)" % (int(size) / 1024.0 ** 2) if size and size.isdigit() and int(size) > 1024 else ""
        return Result(PASS, "Lab box URL", "reachable" + extra)
    except urllib.error.HTTPError as exc:
        return Result(FAIL, "Lab box URL", "HTTP %d for %s" % (exc.code, url),
                      hint_404 if exc.code == 404 else "The server refused the request. Try another box link.")
    except Exception as exc:
        return Result(WARN, "Lab box URL", "could not be reached (%s)" % str(getattr(exc, "reason", exc))[:60],
                      "Check your connection or proxy, then run the check again.")


def check_lab_files(ctx):
    root = ctx["path"]
    if not os.path.isfile(os.path.join(root, "Vagrantfile")):
        return Result(INFO, "Lab files", "no Vagrantfile in %s (run from the lab folder or use --path)" % root)
    results = []
    required = ("core/provision-base.sh", "core/bin/lab-verify.sh", "modules/")
    missing = [rel for rel in required if not os.path.exists(os.path.join(root, *rel.split("/")))]
    if missing:
        results.append(Result(FAIL, "Lab files", "missing: " + ", ".join(missing),
                              "Keep the core/ and modules/ folders next to the Vagrantfile, with their sub-folders."))
    no_readme = [name for name in module_names(root)
                 if not os.path.isfile(os.path.join(root, "modules", name, "README.md"))]
    if no_readme:
        results.append(Result(WARN, "Lab modules", "no README.md in: " + ", ".join(no_readme),
                              "Every module needs a README.md that explains what it teaches."))
    crlf = []
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".vagrant", ".git")]
        for fn in files:
            if fn.endswith(".sh"):
                full = os.path.join(dirpath, fn)
                try:
                    with open(full, "rb") as fh:
                        data = fh.read()
                except Exception:
                    continue
                if b"\r\n" in data:
                    crlf.append(full)
                    if ctx.get("fix_eol"):
                        with open(full, "wb") as fh:
                            fh.write(data.replace(b"\r\n", b"\n"))
    if crlf and ctx.get("fix_eol"):
        results.append(Result(PASS, "Lab files", "converted %d script(s) to Unix line endings" % len(crlf)))
    elif crlf:
        names = ", ".join(os.path.relpath(p, root) for p in crlf[:4]) + (" ..." if len(crlf) > 4 else "")
        results.append(Result(FAIL, "Lab files", "Windows line endings in: " + names,
                              "These scripts will fail inside the VMs. Run: python lab.py check --fix-eol"))
    elif not missing:
        results.append(Result(PASS, "Lab files", "Vagrantfile, core/ and modules/ found; Unix line endings"))
    return results


def module_names(root):
    """Module folders under modules/ (folders starting with . or _ are templates or hidden)."""
    mdir = os.path.join(root, "modules")
    if not os.path.isdir(mdir):
        return []
    return sorted(d for d in os.listdir(mdir)
                  if os.path.isdir(os.path.join(mdir, d)) and not d.startswith((".", "_")))


CHECKS = [check_python, check_platform, check_cpu, check_ram, check_disk, check_path,
          check_virtualization, check_vagrant, check_providers, check_windows_hypervisor,
          check_network, check_box, check_lab_files]


# ---- orchestration ---------------------------------------------------------
def run_checks(ctx, on_result=None):
    results = []
    for fn in CHECKS:
        try:
            out = fn(ctx)
        except Exception as exc:
            out = Result(WARN, fn.__name__.replace("check_", "").replace("_", " ").title(),
                         "check failed to run: %s" % exc, "Include this line when you report the problem.")
        if out is None:
            continue
        for r in (out if isinstance(out, list) else [out]):
            results.append(r)
            if on_result:
                on_result(r)
    return results


def compute_profile(ctx, results):
    if any(r.blocking for r in results):
        return "unsupported"
    ram = ctx.get("ram_gib")
    if ram is not None and ram < MIN_RAM_FULL_GIB:
        return "reduced"
    return "full"


def compute_verdict(results):
    fails = [r for r in results if r.status == FAIL]
    warns = [r for r in results if r.status == WARN]
    if any(r.blocking for r in results):
        return "NOT READY", "This machine cannot run the lab locally. Use another machine or a cloud VM."
    if fails:
        return "NOT READY", "Fix the FAIL items above, then run the check again."
    if warns:
        return "READY WITH WARNINGS", "You can start; review the WARN items when you have time."
    return "READY", "Everything looks good."


def enable_ansi_on_windows():
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)
        mode = ctypes.c_ulong()
        if kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return bool(kernel32.SetConsoleMode(handle, mode.value | 0x0004))
    except Exception:
        pass
    return False


def want_color(args):
    if args.no_color or os.environ.get("NO_COLOR") or not sys.stdout.isatty():
        return False
    if os.name == "nt":
        return enable_ansi_on_windows()
    return os.environ.get("TERM", "") != "dumb"


def format_result(r, color=False):
    tag = "[%s]" % r.status
    if color:
        tag = "\033[%sm%s\033[0m" % (COLORS[r.status], tag)
    lines = ["%s %-18s %s" % (tag, r.name, r.detail)]
    if r.hint and r.status in (WARN, FAIL):
        lines.extend(textwrap.wrap(r.hint, width=74, initial_indent="       -> ", subsequent_indent="          ",
                                  break_on_hyphens=False, break_long_words=False))
    return "\n".join(lines)


def build_ctx(args):
    return {"env": detect_env(), "path": os.path.abspath(args.path), "fix_eol": args.fix_eol,
            "provider_arg": args.provider}


def save_profile(ctx, profile):
    data = {"arch": ctx["env"]["arch"], "os": ctx["env"]["os"], "provider": ctx.get("provider"), "profile": profile,
            "ram_gib": ctx.get("ram_gib"), "generated": datetime.now().isoformat(timespec="seconds"),
            "tool_version": TOOL_VERSION}
    target = os.path.join(ctx["path"], "lab-profile.json")
    with open(target, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    return target


def cmd_check(args):
    ctx = build_ctx(args)
    color = want_color(args)
    if args.json:
        results = run_checks(ctx)
    else:
        print("HPC training cluster preflight check (lab.py %s)" % TOOL_VERSION)
        print("Host: %s, %s\n" % (ctx["env"]["platform"], ctx["env"]["arch"]))
        results = run_checks(ctx, on_result=lambda r: print(format_result(r, color)) or sys.stdout.flush())
    profile = compute_profile(ctx, results)
    verdict, advice = compute_verdict(results)
    saved = None
    if args.save:
        try:
            saved = save_profile(ctx, profile)
        except Exception as exc:
            print("Could not write lab-profile.json: %s" % exc, file=sys.stderr)
    if args.json:
        print(json.dumps({"tool_version": TOOL_VERSION, "os": ctx["env"]["os"], "arch": ctx["env"]["arch"],
                          "provider": ctx.get("provider"), "profile": profile, "verdict": verdict,
                          "results": [r.as_dict() for r in results]}, indent=2))
    else:
        print("\nProvider: %s" % (ctx.get("provider") or "none usable"))
        print("Recommended lab profile: %s" % profile)
        print("Result: %s. %s" % (verdict, advice))
        if verdict.startswith("READY") and ctx.get("provider"):
            print("Next: vagrant up --provider=%s" % ctx["provider"])
        if saved:
            print("Saved: %s" % saved)
    return 0 if verdict.startswith("READY") else 1


def cmd_modules(args):
    root = os.path.abspath(args.path)
    names = module_names(root)
    if not names:
        print("No modules found in %s (run from the lab folder or use --path)." % os.path.join(root, "modules"))
        return 2
    print("Lab modules in %s\n" % root)
    for name in names:
        path = os.path.join(root, "modules", name)
        title = name
        readme = os.path.join(path, "README.md")
        if os.path.isfile(readme):
            with open(readme, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if line.startswith("# "):
                        title = line[2:].strip()
                        break
        bindir = os.path.join(path, "bin")
        tools = sorted(os.path.splitext(f)[0] for f in os.listdir(bindir)) if os.path.isdir(bindir) else []
        print("%s  (%s)" % (title, name))
        print("    tools:       %s" % (", ".join(tools) or "none"))
        if os.path.isfile(os.path.join(path, "provision.sh")):
            # same name rule as the Vagrantfile: the number prefix is dropped
            print("    provisioner: vagrant provision --provision-with %s" % re.sub(r"^\d+-", "", name))
        else:
            print("    provisioner: none")
        print()
    return 0


def safe_name(text):
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", text).strip("-") or "learner"


def cmd_report(args):
    ctx = build_ctx(args)
    print("Running checks for the report (this can take up to a minute)...")
    results = run_checks(ctx)
    profile = compute_profile(ctx, results)
    verdict, advice = compute_verdict(results)
    name = args.name or socket.gethostname()
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    lines = ["HPC training cluster report", "============================",
             "Name:         %s" % name,
             "Generated:    %s" % datetime.now().isoformat(timespec="seconds"),
             "lab.py:       %s" % TOOL_VERSION,
             "Host:         %s, %s" % (ctx["env"]["platform"], ctx["env"]["arch"]),
             "Python:       %s" % platform.python_version(),
             "VirtualBox:   %s" % ctx.get("vbox_version", "not found"),
             "QEMU:         %s" % ctx.get("qemu_version", "not found"),
             "libvirt:      %s" % ctx.get("libvirt_version", "not found"),
             "Vagrant:      %s" % ctx.get("vagrant_version", "not found"),
             "Provider:     %s" % (ctx.get("provider") or "none usable"),
             "Profile:      %s" % profile,
             "Verdict:      %s" % verdict, "", "Checks", "------"]
    lines.extend(format_result(r, False) for r in results)
    if ctx.get("vagrant_path") and os.path.isfile(os.path.join(ctx["path"], "Vagrantfile")):
        rc, out = run([ctx["vagrant_path"], "status"], timeout=60, cwd=ctx["path"])
        lines.extend(["", "vagrant status", "--------------", out or "(no output)"])
    out_path = args.out or os.path.join(ctx["path"], "lab-report-%s-%s.txt" % (safe_name(name), stamp))
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\nReport written to: %s" % out_path)
    print("It contains your name/hostname, OS, CPU architecture, memory, disk space and tool versions. "
          "Attach this file when you ask for help.")
    print("Result: %s. %s" % (verdict, advice))
    return 0 if verdict.startswith("READY") else 1


def main(argv=None):
    parser = argparse.ArgumentParser(prog="lab.py", description="HPC training cluster preflight (Vagrant + VirtualBox, libvirt or QEMU)")
    parser.add_argument("command", nargs="?", default="check", choices=["check", "report", "modules"])
    parser.add_argument("--path", default=".", help="lab folder (default: current folder)")
    parser.add_argument("--provider", choices=["auto", "virtualbox", "libvirt", "qemu"], default="auto",
                        help="virtualization provider to check for (default: auto)")
    parser.add_argument("--save", action="store_true", help="check: write lab-profile.json")
    parser.add_argument("--fix-eol", action="store_true", help="check: convert CRLF to LF in lab *.sh files")
    parser.add_argument("--json", action="store_true", help="check: JSON output")
    parser.add_argument("--no-color", action="store_true", help="disable colored output")
    parser.add_argument("--name", help="report: your name (default: hostname)")
    parser.add_argument("--out", help="report: output file path")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
        except Exception:
            pass
    try:
        commands = {"check": cmd_check, "report": cmd_report, "modules": cmd_modules}
        return commands[args.command](args)
    except KeyboardInterrupt:
        print("\nInterrupted.")
        return 2


if __name__ == "__main__":
    sys.exit(main())
