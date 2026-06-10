# Virtual machines — QEMU/KVM + virt-manager

A **virtual machine** is a whole computer simulated in software: its own BIOS/UEFI,
disk, CPU, RAM and network, running a guest operating system that has no idea it
isn't on real hardware. It's the safest possible sandbox — you can install
Gentoo, break it, wipe it, and start over without touching your real system. For
**learning to build Gentoo** or **Linux From Scratch**, that throwaway-and-retry
loop is the whole point.

This page covers the stack `install.sh vm` sets up: **QEMU** (the machine
emulator), **KVM** (the kernel feature that makes it fast), **libvirt** (the
manager), and **virt-manager** (the GUI).

---

## The 30-second recipe

```bash
bash install.sh vm              # qemu-full + libvirt + virt-manager + friends
# log out + back in (the libvirt + kvm groups need a fresh session)

virt-manager                    # the GUI opens, already connected to qemu:///system
# - File ▸ New Virtual Machine
# - point it at a downloaded ISO (Gentoo minimal, an LFS host distro, …)
# - give it disk + RAM + CPUs, finish, and it boots into the installer
```

That's it. The default NAT network is already running, so the guest has internet
the moment it boots.

---

## QEMU vs KVM vs libvirt vs virt-manager — who does what

These four names get used interchangeably, but they're four layers:

| Layer | What it is | Analogy |
|---|---|---|
| **QEMU** | The actual emulator. Pretends to be a PC (or an ARM board, a RISC-V box…). Can run **any** guest arch on **any** host by translating instructions. | The engine |
| **KVM** | A **kernel** feature (`/dev/kvm`). When the guest arch == host arch, it runs guest CPU instructions **directly on your real CPU** instead of translating them — near-native speed. QEMU uses it automatically when it can. | The turbocharger |
| **libvirt** | A daemon + API that defines, starts, stops and snapshots VMs, manages virtual networks and storage pools, and stores each VM as an XML file. | The fleet manager |
| **virt-manager** | A GTK GUI on top of libvirt. (`virsh` is the CLI for the same thing.) | The dashboard |

So: virt-manager talks to libvirt, libvirt drives QEMU, QEMU uses KVM to go fast.
You'll mostly live in virt-manager and never think about the layers below — but
when something is slow or broken, knowing which layer owns the problem is half
the fix.

!!! tip "Emulation is *also* why `qemu-full`"
    With `qemu-full` you get every guest architecture, not just x86_64. You can
    boot an **ARM64** or **RISC-V** image on this Intel/AMD box (slowly — that
    path is pure emulation, no KVM) which is great for cross-arch LFS
    experiments or testing a Raspberry-Pi image before flashing it.

---

## Why KVM needs nothing special on either kernel

This box keeps **two kernels** (`linux` and `linux-lts` — see the
[NVIDIA](../arch/nvidia.md) and [maintenance](../arch/system-maintenance.md) pages for
why). A reasonable worry is whether the VM stack needs setting up twice, once
per kernel — the way DKMS modules (like the NVIDIA driver) get rebuilt for each.

**It doesn't.** KVM is *built into the kernel itself*. The modules —

- `kvm` (the core),
- `kvm_intel` **or** `kvm_amd` (your CPU's hardware-virt extensions),
- `vhost` / `vhost_net` (fast paravirtualised I/O),

— ship **in-tree** with every Arch kernel package. There's no out-of-tree
module to compile, so there's nothing to rebuild when you switch kernels or when
a kernel updates. Boot `linux` or `linux-lts`, and `/dev/kvm` is simply there.

The *only* kernel-touching file `install.sh vm` writes is
`/etc/modprobe.d/kvm-nested.conf` (nested virt, below). modprobe options are
read at **module load time** by whatever kernel is currently running, so that
one file correctly applies to both kernels too. One install covers everything.

### Check it's actually working

```bash
# 1. Your CPU exposes hardware virtualisation (VT-x on Intel, AMD-V on AMD):
LC_ALL=C lscpu | grep Virtualization
#   -> "Virtualization: VT-x"  (or "AMD-V"). Blank = turn it on in UEFI/BIOS.

# 2. The kernel module is loaded:
lsmod | grep kvm
#   -> kvm_intel (or kvm_amd) and kvm

# 3. The device node exists and you can reach it:
ls -l /dev/kvm
#   -> crw-rw---- root kvm   (you're in the kvm group after logout/login)
```

If `lscpu` shows nothing for Virtualization, it's a **firmware** setting, not a
Linux one: reboot into UEFI setup and enable *Intel VT-x / VT-d* or *AMD SVM*.

---

## What `install.sh vm` wires up

Installing the packages is the easy part; the component also does the plumbing
that otherwise trips people up on a fresh Arch box:

1. **Groups.** Adds you to **`libvirt`** (so you manage the *system* QEMU
   instance, `qemu:///system`, without a polkit password every time) and
   **`kvm`** (direct access to `/dev/kvm`). Like every group change in these
   scripts, **it only applies after a fresh login** — verify with
   `groups | tr ' ' '\n' | grep -E 'libvirt|kvm'`.
2. **Socket ownership.** Sets `unix_sock_group = "libvirt"` and
   `unix_sock_rw_perms = "0770"` in `/etc/libvirt/libvirtd.conf` so the
   `libvirt` group owns libvirt's control socket.
3. **The daemon.** `systemctl enable --now libvirtd.service` (it socket-activates
   and pulls in `virtlogd`/`virtlockd` as needed).
4. **The default network.** Defines (if missing), autostarts and starts
   libvirt's **default NAT network**. This gives every guest a private
   `192.168.122.0/24` address with DHCP and outbound internet through your host —
   no bridge setup, no router config. `dnsmasq` is what hands out those leases,
   which is why it's in the package list.
5. **Nested virtualisation.** Writes `/etc/modprobe.d/kvm-nested.conf` with the
   right option for your CPU (`options kvm_intel nested=1` or
   `options kvm_amd nested=1`, auto-detected). See below.

---

## `qemu:///system` vs `qemu:///session`

libvirt has two connections and the difference bites beginners:

- **`qemu:///system`** — VMs run under a system-wide libvirtd as a dedicated
  user. They can use the default NAT network, autostart at boot, and live in
  `/var/lib/libvirt/images`. This is what the `libvirt` group grants you and
  what virt-manager connects to here. **Use this one.**
- **`qemu:///session`** — a per-user libvirtd, no root, but networking is
  limited (usermode SLIRP, slower, no inbound). Handy on locked-down machines;
  unnecessary here.

If virt-manager ever shows "Not Connected", it's almost always that you haven't
logged out/in since the install (so you're not yet in the `libvirt` group), or
`libvirtd` isn't running (`systemctl status libvirtd`).

---

## Your first guest — Gentoo or LFS

The settings that matter for a smooth, fast Linux guest:

1. **Firmware: UEFI.** In the "New VM" wizard, expand *Customize before install*
   and set Firmware to **UEFI** (`edk2-ovmf` provides it). Modern installers
   expect it, and it matches how real hardware boots now.
2. **Chipset: Q35.** The modern virtual chipset (PCIe, proper UEFI). The old
   default `i440fx` is legacy.
3. **Disk bus: VirtIO.** When you add the disk, set its bus to **VirtIO** rather
   than SATA/IDE. VirtIO is a *paravirtualised* device — the guest knows it's
   virtual and talks an efficient protocol straight to the host instead of
   pretending to poke real disk-controller registers. Same for the **NIC model:
   virtio**. The Linux kernel has VirtIO drivers built in, so Gentoo/LFS see
   the disk and network immediately. (Disk image format: **qcow2** —
   thin-provisioned and snapshot-capable.)
4. **CPUs & RAM.** For *compiling* a distro, throw cores at it — Gentoo's
   `emerge` and LFS's `make -j` are embarrassingly parallel. 4–8 vCPUs and
   8–16 GB RAM make the build hours instead of days. Set CPU model to
   **host-passthrough** so the guest sees your real CPU's instruction set
   (faster compiles, and `-march=native` actually means something).
5. **Where the disk lives.** By default guest disks go to
   `/var/lib/libvirt/images`, which is on the **root partition** (~50 GB here).
   A Gentoo/LFS build image can be 20–40 GB. Either keep guests small, or point
   the storage pool at **`/home`** (≈880 GB) — *Edit ▸ Connection Details ▸
   Storage* in virt-manager, add a pool under e.g. `/home/vms`. (This box's
   convention is "big data lives on `/home`" — same reason Docker's data-root
   was moved there.)

!!! note "Why a VM is the right tool for LFS specifically"
    Linux From Scratch has you compile a toolchain and then a whole userland by
    hand; one wrong `./configure` flag can leave the system unbootable. In a VM
    you take a **snapshot** before each risky chapter (virt-manager ▸ the
    snapshot icon) and roll back in seconds instead of restarting the book.

---

## Performance tuning (when builds feel slow)

The defaults above already get you ~90% of native. If you want the rest:

- **`host-passthrough` CPU** (mentioned above) — biggest single win for
  compile-heavy guests.
- **Hugepages** — back the guest's RAM with 2 MB pages to cut TLB misses.
  Allocate on the host (`vm.nr_hugepages` via sysctl) and tick *Enable shared
  memory* / set `<memoryBacking><hugepages/>` in the guest XML.
- **CPU pinning** — pin vCPUs to specific host cores so the scheduler stops
  bouncing them across the cache hierarchy. Worth it for long `emerge` runs.
- **`io='native'` + `cache='none'` on the disk** — direct I/O, skips the host
  page cache (which would otherwise double-cache). Set in the disk's *Advanced
  options*.
- **virtio-blk vs virtio-scsi** — virtio-blk is simplest and fastest for a
  single disk; virtio-scsi if you want TRIM/discard to shrink qcow2 files.

You won't need any of this just to *learn* Gentoo — start with the New-VM
defaults plus VirtIO + UEFI + host-passthrough, and only tune if a build is
painfully slow.

---

## Nested virtualisation

`install.sh vm` enables **nested virt** — running KVM *inside* a guest. Useful
when you want to:

- test a hypervisor or a cloud image that itself launches VMs, or
- run a VM inside your Gentoo/LFS guest to test what you built.

It's off in the kernel by default; the component writes the per-vendor module
option. Verify after a reboot (or module reload):

```bash
cat /sys/module/kvm_intel/parameters/nested     # Intel  -> "Y"  (or "1")
cat /sys/module/kvm_amd/parameters/nested        # AMD    -> "Y"
```

Then, in the guest's CPU config, use **host-passthrough** (or tick *Copy host
CPU configuration*) so the guest sees the `vmx`/`svm` flag and can load its own
KVM.

---

## Networking quick reference

- **Default NAT** (what you get out of the box): guest can reach the internet
  and the host; the outside LAN **cannot** reach the guest. Perfect for
  building/installing distros. Range `192.168.122.0/24`.
- **Bridged** (advanced): the guest gets an IP on your real LAN, like a separate
  physical machine. Needs a host bridge interface; only set this up if you want
  other machines to connect *into* the guest.
- **Host-only / isolated**: guests talk to each other and the host but have no
  internet. For air-gapped experiments.

```bash
virsh net-list --all          # see networks + state
virsh net-info default        # details of the NAT network
```

---

## Day-to-day `virsh` (the CLI behind the GUI)

Everything virt-manager does, `virsh` does scriptably:

```bash
virsh list --all                       # all VMs and their state
virsh start  gentoo                     # boot a VM
virsh shutdown gentoo                   # ACPI shutdown
virsh destroy gentoo                    # force-off (pulls the plug)
virsh snapshot-create-as gentoo pre-ch6 # snapshot before a risky step
virsh snapshot-revert gentoo pre-ch6    # roll back
virsh console gentoo                    # serial console (if the guest enables one)
virsh dominfo gentoo                    # CPU/RAM/state summary
```

---

## Reverting / reclaiming disk

```bash
bash uninstall.sh vm
```

This is a **clean** removal — it stops the daemon and default network, removes
the whole stack (`qemu-full` + its sub-packages, `libvirt`, `virt-manager`,
`virt-viewer`, `edk2-ovmf`, `swtpm`, `libguestfs`, and `dnsmasq`/`dmidecode` if
nothing else needs them), and **deletes all guest disk images in every storage
pool** — not only the default `/var/lib/libvirt` one but also any **custom pool
you put on `/home`** (e.g. a `gentoo` pool pointing at `~/Documents/linux-iso/…`),
which is where the real gigabytes are after building a few Gentoo/LFS images. It
also clears `/etc/libvirt` (your pool definitions), your per-user virt-manager
state, the nested-virt modprobe drop-in, and drops your `libvirt`/`kvm` group
memberships. The reclaim tally at the end shows how much space you got back.

!!! tip "You don't have to clean up in virt-manager first"
    The two ways to free a VM's disk:

    1. **In virt-manager** — right-click the VM ▸ *Delete*, and **tick "Delete
       associated storage files"**. Use this when you want to remove *one* VM but
       keep the virtualization stack for later (e.g. move on to LFS).
    2. **`bash uninstall.sh vm`** — rips out the whole stack. It now also **sweeps
       custom pools**, so even if you *forgot* to tick that box, the orphaned
       `.qcow2` sitting in your `/home` pool is found and reclaimed anyway.

    Either way, your downloaded **ISO is left alone** — the script removes only real
    VM disk images (`.qcow2`/`.raw`/`.img`/…) and prints the path of anything it
    skipped (ISOs, stray files) so you can delete it by hand. Remove an ISO with a
    plain `rm`, e.g. `rm ~/Documents/linux-iso/gentoo/*.iso`.

!!! warning "It deletes your VMs"
    `uninstall.sh vm` deletes the disk image of **every** guest in **every** pool,
    so all your VMs go with it. If you've built something you want to keep, copy the
    `.qcow2` out (from `/var/lib/libvirt/images` or your `/home` pool) first.

The KVM kernel modules are in-tree, so there's nothing to uninstall there — they
go dormant the moment nothing uses `/dev/kvm`.
