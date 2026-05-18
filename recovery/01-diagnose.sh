#!/bin/bash
# Run from inside the Server4You Rescue-Modus shell, AFTER:
#   mdadm --assemble --scan
#   mount /dev/md1p1 /mnt
#
# Read-only diagnostics. Touches nothing. Produces a single report you can
# paste back so the next step is precise.

set -u
MNT="${MNT:-/mnt}"
REPORT="/tmp/recovery-diagnose.txt"

run() {
    local label="$1"; shift
    echo "======== $label ========" >> "$REPORT"
    "$@" >> "$REPORT" 2>&1 || echo "(exit=$?)" >> "$REPORT"
    echo >> "$REPORT"
}

: > "$REPORT"

echo "Writing diagnostic report to $REPORT ..."

run "uname"                   uname -a
run "rescue date"             date
run "mounts"                  mount
run "lsblk"                   lsblk -f
run "mdstat"                  cat /proc/mdstat
run "is /mnt populated"       ls -la "$MNT"
run "os-release"              cat "$MNT/etc/os-release"
run "fstab (CRITICAL)"        cat "$MNT/etc/fstab"
run "resolv.conf"             ls -la "$MNT/etc/resolv.conf"
run "resolv.conf body"        cat "$MNT/etc/resolv.conf"
run "hostname"                cat "$MNT/etc/hostname"
run "hosts"                   cat "$MNT/etc/hosts"

# Boot
run "boot listing"            ls -la "$MNT/boot"
run "grub.cfg head"           head -50 "$MNT/boot/grub/grub.cfg"

# Kernels installed
run "kernels in /boot"        bash -c "ls $MNT/boot/vmlinuz-* $MNT/boot/initrd.img-* 2>&1"

# dpkg state
run "dpkg lock"               ls -la "$MNT/var/lib/dpkg/lock" "$MNT/var/lib/dpkg/lock-frontend"
run "dpkg updates dir"        ls -la "$MNT/var/lib/dpkg/updates/"
run "apt history (tail)"      tail -n 200 "$MNT/var/log/apt/history.log"
run "apt term log (tail)"     tail -n 200 "$MNT/var/log/apt/term.log"
run "dpkg log (tail)"         tail -n 200 "$MNT/var/log/dpkg.log"

# Critical package states (these are the ones Gemini's dist-upgrade marked for removal)
echo "======== critical package states ========" >> "$REPORT"
for pkg in init systemd-sysv systemd libpam-systemd libnss-systemd udev \
           netplan.io initramfs-tools openssh-server openssh-client \
           libc6 libc-bin libssl3t64 libssl3 ca-certificates dbus \
           libreadline8t64 libreadline8 grub-pc grub-efi-amd64 \
           docker-ce docker.io containerd.io caddy nginx; do
    state=$(chroot "$MNT" dpkg-query -W -f='${db:Status-Abbrev} ${Version}' "$pkg" 2>&1 | head -1)
    printf "  %-25s %s\n" "$pkg" "$state" >> "$REPORT"
done
echo >> "$REPORT"

# Half-installed / failed packages
run "half-installed pkgs"     bash -c "chroot $MNT dpkg -l | awk '\$1 !~ /^ii/ && \$1 !~ /^un/ && NR>5 {print}'"

# SSH
run "sshd_config (active)"    bash -c "grep -vE '^[[:space:]]*(#|$)' $MNT/etc/ssh/sshd_config"
run "sshd_config.d files"     ls -la "$MNT/etc/ssh/sshd_config.d/"
for f in "$MNT"/etc/ssh/sshd_config.d/*; do
    [ -f "$f" ] || continue
    run "  -> $(basename "$f")" cat "$f"
done
run "root .ssh listing"       ls -la "$MNT/root/.ssh/"
run "root authorized_keys"    cat "$MNT/root/.ssh/authorized_keys"
run "stat .ssh"               stat "$MNT/root" "$MNT/root/.ssh" "$MNT/root/.ssh/authorized_keys"

# Users
run "root in /etc/passwd"     grep '^root:' "$MNT/etc/passwd"
run "root shadow exists"      bash -c "grep '^root:' $MNT/etc/shadow | awk -F: '{print \$1, (\$2==\"!\" || \$2==\"*\" || \$2~/^!/) ? \"LOCKED\" : \"HAS_HASH\"}'"

# PAM (libpam-systemd was scheduled for removal — this matters)
run "pam.d/sshd"              cat "$MNT/etc/pam.d/sshd"
run "pam.d/common-session"    cat "$MNT/etc/pam.d/common-session"
run "pam.d/common-auth"       cat "$MNT/etc/pam.d/common-auth"

# Networking
run "netplan dir"             ls -la "$MNT/etc/netplan/"
for f in "$MNT"/etc/netplan/*.yaml "$MNT"/etc/netplan/*.yml; do
    [ -f "$f" ] || continue
    run "  -> $(basename "$f")" cat "$f"
done
run "systemd-networkd dir"    ls -la "$MNT/etc/systemd/network/"
run "interfaces (legacy)"     bash -c "ls $MNT/etc/network/ 2>/dev/null && cat $MNT/etc/network/interfaces 2>/dev/null"
run "nsswitch"                cat "$MNT/etc/nsswitch.conf"

# Firewall
run "ufw status file"         bash -c "cat $MNT/etc/ufw/ufw.conf 2>/dev/null"
run "iptables save"           bash -c "find $MNT/etc -name 'iptables*' -o -name 'rules.v*' 2>/dev/null | xargs -r ls -la"
run "nftables conf"           bash -c "cat $MNT/etc/nftables.conf 2>/dev/null"
run "fail2ban jail.local"     bash -c "cat $MNT/etc/fail2ban/jail.local 2>/dev/null; echo '--- target ---'; cat $MNT/home/mail_new/rendered/fail2ban/jail.local 2>/dev/null"

# Sources list
run "sources.list"            cat "$MNT/etc/apt/sources.list"
run "sources.list.d"          ls -la "$MNT/etc/apt/sources.list.d/"
for f in "$MNT"/etc/apt/sources.list.d/*.list "$MNT"/etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    run "  -> $(basename "$f")" cat "$f"
done

# Web / Docker
run "/var/log listing"        bash -c "ls -la $MNT/var/log/ 2>&1 | head -50"
run "/var/log/journal"        bash -c "ls -la $MNT/var/log/journal/ 2>&1 | head -20"
run "docker present"          bash -c "ls -la $MNT/var/lib/docker/ 2>&1 | head"
run "/etc/docker"             bash -c "ls -la $MNT/etc/docker/ 2>&1; cat $MNT/etc/docker/daemon.json 2>/dev/null"
run "caddy dir (tkb)"         bash -c "ls -la $MNT/home/tkb/vibe_code/caddy/ 2>&1"
run "Caddyfile"               bash -c "find $MNT -maxdepth 6 -name Caddyfile 2>/dev/null"

# Lost+found may indicate fsck found corruption from the hard reset
run "lost+found"              bash -c "ls -la $MNT/lost+found/ 2>&1 | head"

echo "======== END ========" >> "$REPORT"
echo
echo "Report ready. Send back the contents of: $REPORT"
echo "Size: $(wc -l < "$REPORT") lines, $(wc -c < "$REPORT") bytes"
