#!/bin/bash
#
# Server4You rescue → repair script
# Run AFTER 01-diagnose.sh and AFTER reviewing the report.
#
# Prereqs in rescue shell:
#   mdadm --assemble --scan
#   mount /dev/md1p1 /mnt
#
# What this does, in order:
#   1. Refuses to run if /mnt doesn't look like the broken root.
#   2. Bind-mounts /dev /dev/pts /proc /sys /run for chroot.
#   3. Gives the chroot working DNS.
#   4. Finishes the interrupted dpkg transaction (dpkg --configure -a).
#   5. Reinstalls the essential packages the Gemini run wiped or half-removed,
#      pinning to the codename it can actually fetch.
#   6. Runs apt --fix-broken install (NO dist-upgrade, NO autoremove).
#   7. Restores /etc/resolv.conf to a systemd-resolved-compatible state.
#   8. Verifies /root/.ssh perms, sshd_config, root account not locked.
#   9. Regenerates initramfs and grub.
#   10. Cleans up mounts.
#
# This does NOT reboot. You exit Rescue-Modus from the PowerPanel.
#
# All steps log to /tmp/recovery-repair.log
#

set -u
MNT="${MNT:-/mnt}"
LOG="/tmp/recovery-repair.log"

log()  { echo "[$(date +%T)] $*" | tee -a "$LOG"; }
die()  { log "FATAL: $*"; exit 1; }
run()  { log "+ $*"; "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }
crun() { log "[chroot] + $*"; chroot "$MNT" bash -c "$*" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }

: > "$LOG"
log "=== Repair starting ==="

# ---------- 1. Sanity ----------
[ "$(id -u)" = 0 ] || die "Must be root."
mountpoint -q "$MNT" || die "$MNT is not a mountpoint. Run: mount /dev/md1p1 /mnt"
[ -d "$MNT/etc" ] && [ -d "$MNT/var" ] && [ -d "$MNT/root" ] \
    || die "$MNT does not look like a Linux root (no etc/var/root)."
[ -x "$MNT/bin/bash" ] || [ -x "$MNT/usr/bin/bash" ] \
    || die "$MNT has no bash — wrong partition?"

log "Mountpoint OK: $MNT"

# ---------- 2. Bind mounts ----------
log "--- Setting up chroot bind mounts ---"
for src in /dev /dev/pts /proc /sys /run; do
    tgt="$MNT$src"
    mkdir -p "$tgt"
    if ! mountpoint -q "$tgt"; then
        if [ "$src" = "/dev" ] || [ "$src" = "/run" ]; then
            run mount --rbind "$src" "$tgt"
            run mount --make-rslave "$tgt"
        else
            run mount --bind "$src" "$tgt"
        fi
    fi
done

cleanup() {
    log "--- Cleaning up bind mounts ---"
    for tgt in "$MNT/run" "$MNT/sys" "$MNT/proc" "$MNT/dev/pts" "$MNT/dev"; do
        if mountpoint -q "$tgt"; then
            umount -lf "$tgt" 2>&1 | tee -a "$LOG" || true
        fi
    done
    log "Cleanup done. Log: $LOG"
}
trap cleanup EXIT

# ---------- 3. DNS inside chroot ----------
log "--- DNS for chroot ---"
# If resolv.conf is a broken symlink (to /run/systemd/resolve/...), replace it
# with a real file. We will restore the systemd symlink at the end if appropriate.
if [ -L "$MNT/etc/resolv.conf" ] && [ ! -e "$MNT/etc/resolv.conf" ]; then
    log "resolv.conf is a dangling symlink — replacing temporarily."
    rm "$MNT/etc/resolv.conf"
fi
cat > "$MNT/etc/resolv.conf" <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Sanity test network from chroot
if ! crun "getent hosts archive.ubuntu.com >/dev/null"; then
    log "WARNING: DNS lookup failed inside chroot. Check rescue networking."
fi

# ---------- 4. Finish interrupted dpkg ----------
log "--- dpkg --configure -a (finish interrupted transaction) ---"
crun "DEBIAN_FRONTEND=noninteractive dpkg --configure -a" || \
    log "dpkg --configure -a exited non-zero — continuing, apt will retry."

# ---------- 5. Make sure sources are sane (noble only) ----------
log "--- Checking apt sources ---"
crun "grep -rE '^[[:space:]]*deb' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -vE 'noble|^#'" \
    && log "WARN: Non-noble sources found. Review before continuing if you want." \
    || log "Sources look noble-only."

# ---------- 6. apt update + reinstall essentials ----------
log "--- apt update ---"
crun "DEBIAN_FRONTEND=noninteractive apt-get update" || die "apt-get update failed."

log "--- Reinstalling critical packages that were removed/half-installed ---"
# These are the packages from the 'will be REMOVED' block in the Gemini run.
# We reinstall instead of upgrade so apt doesn't try to remove init/systemd-sysv again.
ESSENTIAL=(
    libc6 libc-bin
    init systemd-sysv systemd systemd-resolved
    libpam-systemd libnss-systemd
    udev dbus dbus-user-session
    netplan.io
    initramfs-tools initramfs-tools-core
    openssh-server openssh-client
    ca-certificates
    grub-pc grub-common grub2-common
    libssl3t64 libreadline8t64
)
crun "DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y --no-install-recommends ${ESSENTIAL[*]}" \
    || log "Some essentials failed to install; continuing — apt -f install will retry."

log "--- apt --fix-broken install ---"
crun "DEBIAN_FRONTEND=noninteractive apt-get -f install -y -o Dpkg::Options::='--force-confold' -o Dpkg::Options::='--force-confdef'" \
    || log "apt -f install non-zero — re-running dpkg --configure -a."

crun "DEBIAN_FRONTEND=noninteractive dpkg --configure -a" || true

# ---------- 7. SSH sanity ----------
log "--- SSH verification ---"
SSHD_CFG="$MNT/etc/ssh/sshd_config"
if [ -f "$SSHD_CFG" ]; then
    # Ensure the basics needed for key-based root login
    sed -i \
        -e 's/^[#[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
        -e 's|^[#[:space:]]*AuthorizedKeysFile.*|AuthorizedKeysFile .ssh/authorized_keys|' \
        -e 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin prohibit-password/' \
        "$SSHD_CFG"
    grep -qE '^PubkeyAuthentication yes' "$SSHD_CFG" || echo 'PubkeyAuthentication yes' >> "$SSHD_CFG"
    grep -qE '^PermitRootLogin (yes|prohibit-password)' "$SSHD_CFG" \
        || echo 'PermitRootLogin prohibit-password' >> "$SSHD_CFG"
    log "sshd_config patched."
else
    log "WARN: sshd_config missing — openssh-server reinstall above should have placed it."
fi

# .ssh permissions
if [ -d "$MNT/root/.ssh" ]; then
    run chown -R 0:0 "$MNT/root/.ssh"
    run chmod 700 "$MNT/root/.ssh"
    [ -f "$MNT/root/.ssh/authorized_keys" ] && run chmod 600 "$MNT/root/.ssh/authorized_keys"
    log "Root .ssh permissions normalized."
    log "authorized_keys contents:"
    cat "$MNT/root/.ssh/authorized_keys" 2>&1 | tee -a "$LOG" | head
else
    log "WARN: /root/.ssh does not exist. SSH key login will fail until you re-add a key."
fi

# Make sure root isn't locked
crun "passwd -S root" | tee -a "$LOG"
crun "passwd -u root 2>/dev/null || true"

# ---------- 8. Network sanity ----------
log "--- Netplan files ---"
if [ -d "$MNT/etc/netplan" ]; then
    ls -la "$MNT/etc/netplan/" | tee -a "$LOG"
    for f in "$MNT"/etc/netplan/*.yaml "$MNT"/etc/netplan/*.yml; do
        [ -f "$f" ] || continue
        log "  $f:"
        sed 's/^/    /' "$f" | tee -a "$LOG"
    done
else
    log "WARN: no /etc/netplan directory."
fi

# Restore systemd-resolved managed resolv.conf only if the service file exists
if [ -e "$MNT/run/systemd/resolve" ] || [ -e "$MNT/lib/systemd/system/systemd-resolved.service" ]; then
    log "Leaving /etc/resolv.conf as static file. systemd-resolved will repoint it on first boot if active."
fi

# ---------- 9. initramfs + grub ----------
log "--- Regenerating initramfs ---"
crun "update-initramfs -u -k all" || log "update-initramfs failed; may still be ok if no kernel changed."

log "--- Updating GRUB ---"
crun "update-grub" || log "update-grub failed."

# ---------- 10. Final state ----------
log "--- Final dpkg health ---"
crun "dpkg -l | awk '\$1 !~ /^ii/ && \$1 !~ /^un/ && NR>5'" | tee -a "$LOG"

log "=== Repair finished ==="
log "Review $LOG, then:"
log "  exit chroot context (this script already does that)"
log "  umount $MNT  (the trap will unmount the binds; run umount $MNT yourself last)"
log "  Disable Rescue-Modus in Server4You PowerPanel"
log "  Trigger reboot from PowerPanel"
