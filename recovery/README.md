# Emergency Server Recovery — Server4You Rescue-Modus

Context: Ubuntu 24.04 (Noble) on Server4You dedicated, software RAID1 (sda3+sdb3
→ md1, with a GPT partition table inside md1 → md1p1 holds the rootfs; md0p1 is
swap). An interrupted `apt dist-upgrade` confirmed removal of essential
packages (`init`, `systemd-sysv`, `libpam-systemd`, `libnss-systemd`, `udev`,
`netplan.io`, `initramfs-tools`, etc.) and was then hard-reset via
`echo b > /proc/sysrq-trigger` mid-flight.

Symptoms now: server unreachable; key-based SSH no longer works (PAM
session/NSS gone); web stack (Caddy + Docker) doesn't come up.

## Usage

From the Server4You **Rescue-Modus** SSH session (root):

```bash
# 1. Assemble RAID and mount the rootfs
mdadm --assemble --scan
mount /dev/md1p1 /mnt

# 2. Pull or paste the scripts into the rescue shell, e.g.:
#    curl -sSLo /tmp/01-diagnose.sh https://.../recovery/01-diagnose.sh
#    curl -sSLo /tmp/02-repair.sh   https://.../recovery/02-repair.sh
chmod +x /tmp/01-diagnose.sh /tmp/02-repair.sh

# 3. Diagnose first (read-only)
bash /tmp/01-diagnose.sh
cat /tmp/recovery-diagnose.txt   # review

# 4. If the report looks sane, repair
bash /tmp/02-repair.sh
cat /tmp/recovery-repair.log     # review

# 5. Unmount and exit Rescue-Modus from PowerPanel
umount /mnt
#   then in PowerPanel: disable Rescue-Modus → reboot
```

## What `02-repair.sh` deliberately does NOT do

- No `apt dist-upgrade` (that's what blew up the system in the first place).
- No `apt autoremove` (will happily remove essentials again).
- No `--force-depends` `dpkg` invocations.
- No reboot. You exit rescue from the provider panel — running `reboot` inside
  rescue boots straight back into rescue.

## After reboot

If SSH key login still fails, the most likely remaining causes are, in order:

1. `/root/.ssh/authorized_keys` was wiped or empty — re-add the key.
2. `PasswordAuthentication no` plus no key → use rescue + chroot to fix.
3. Fail2ban banned you on the *previous, working* server — irrelevant here,
   the SQLite DB had only stale July-2025 entries from hostname `astra2419`.

For the Caddy/Docker side (HTTP 502s seen in the May 9 logs predate this
incident; they indicate the PHP backend container was already crashing
pre-upgrade — separate issue from the SSH outage).
