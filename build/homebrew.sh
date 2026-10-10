#!/usr/bin/env bash
# Homebrew, the Bluefin / Universal Blue way. The payload and units come from ghcr.io/ublue-os/brew
# (Apache-2.0; Homebrew itself is BSD-2-Clause), pinned by digest in the Containerfile and copied in by
# `COPY --from=brew /system_files /`:
#   /usr/share/homebrew.tar.zst      prebuilt /home/linuxbrew/.linuxbrew
#   brew-setup.service               first boot: unpacks it to /home/linuxbrew (= /var/home/linuxbrew),
#                                    chowns it to 1000:1000 (the first user), touches /etc/.linuxbrew
#   brew-update/brew-upgrade.timer   periodic `brew update` / `brew upgrade` as UID 1000
#   /etc/profile.d/brew.sh           brew shellenv for interactive bash/zsh, PATH APPENDED after the
#                                    system paths; /usr/share/fish/vendor_conf.d/ublue-brew.fish for fish
# This step verifies the payload (SHA-256 below, update it together with the digest), adds a tmpfiles.d
# entry for /var/home/linuxbrew, ships the optional Brewfile and tags all of it with the user.component
# xattr so the 150 MB tarball gets its own rechunked layer instead of sitting in the shared one.
set -xeuo pipefail

TARBALL=/usr/share/homebrew.tar.zst
TARBALL_SHA256=d64945182890cf879928ffe71fd3681758a699d01e5156974d762e1e307c6a19
COMPONENT=homebrew

rpm -q attr >/dev/null || dnf -y install attr

echo "${TARBALL_SHA256}  ${TARBALL}" | sha256sum -c -
tar --zstd -tf "${TARBALL}" > /tmp/homebrew.list   # to a file: grep -q on a pipe trips pipefail (SIGPIPE)
grep -qx 'home/linuxbrew/.linuxbrew/bin/brew' /tmp/homebrew.list
grep -qx 'home/linuxbrew/.linuxbrew/Homebrew/LICENSE.txt' /tmp/homebrew.list
rm -f /tmp/homebrew.list

UNITS="brew-setup.service brew-update.service brew-update.timer brew-upgrade.service brew-upgrade.timer"
for u in ${UNITS}; do test -f "/usr/lib/systemd/system/${u}"; done
grep -q 'chown -R 1000:1000 /home/linuxbrew' /usr/lib/systemd/system/brew-setup.service
# brew must come after the system paths
grep -q 'export PATH="${PATH}:${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin"' /etc/profile.d/brew.sh
test -f /usr/share/fish/vendor_conf.d/ublue-brew.fish

# /home -> /var/home on bootc. brew-setup.service creates and chowns the tree; this keeps the top
# directory present and owned by the first user (UID/GID 1000) on every boot, without a recursive walk.
cat > /usr/lib/tmpfiles.d/dank-ws-homebrew.conf <<'EOT'
# Homebrew prefix parent (see build/homebrew.sh); brew-setup.service unpacks .linuxbrew below it.
d /var/home/linuxbrew 0755 1000 1000 -
EOT

install -D -m 0644 /run/build/Brewfile /usr/share/dank-ws/Brewfile
grep -q '^brew "eza"' /usr/share/dank-ws/Brewfile

for f in "${TARBALL}" /usr/lib/systemd/system/brew-* /usr/lib/systemd/system-preset/01-homebrew.preset \
         /etc/profile.d/brew.sh /etc/profile.d/brew-bash-completion.sh /etc/security/limits.d/30-brew-limits.conf \
         /usr/share/fish/vendor_conf.d/ublue-brew.fish /usr/lib/tmpfiles.d/dank-ws-homebrew.conf \
         /usr/share/dank-ws/Brewfile; do
    if [[ -f "$f" && ! -L "$f" ]]; then setfattr -n user.component -v "${COMPONENT}" "$f"; fi
done
test "$(getfattr --absolute-names -n user.component --only-values "${TARBALL}")" = "${COMPONENT}"
