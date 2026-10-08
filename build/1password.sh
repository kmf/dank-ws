#!/usr/bin/env bash
# 1Password desktop app (official RPM, https://downloads.1password.com/linux/rpm/stable/), both image
# variants. Same idea as Universal Blue's 1Password installer (ublue-os/bling installers/1password.sh),
# adapted to a dnf container build:
#   - the RPM installs to /opt/1Password, but /opt is /var/opt on a bootc system (not part of the
#     image), so the tree is moved to /usr/lib/1Password and /opt/1Password is recreated at boot as a
#     symlink by tmpfiles.d (paths 1Password hardcodes, e.g. /opt/1Password/op-ssh-sign, keep working);
#   - the RPM's post-install creates the `onepassword` / `onepassword-mcp` groups with groupadd. Groups
#     made at build time only land in the image's /etc/group, which bootc does not merge into an
#     existing system's modified /etc/group, so they are declared in sysusers.d with FIXED GIDs (the
#     setgid helpers are chgrp'd to these numbers at build time, so the GIDs must match everywhere);
#   - Wayland: /usr/bin/1password is a small wrapper that adds --ozone-platform=wayland in a Wayland
#     session (see below), and both .desktop files launch it.
# Every file of the app is tagged with the user.component xattr, so rechunking puts it into its own
# layers and a 1Password update does not touch the shared, DMS or Tailscale layers.
set -xeuo pipefail

GID_ONEPASSWORD=1500       # same GID Universal Blue uses
GID_ONEPASSWORD_MCP=1700   # 1600 is Universal Blue's onepassword-cli GID; keep it free
APP_DIR=/usr/lib/1Password
COMPONENT=1password

rpm -q attr >/dev/null || dnf -y install attr

# Fixed-GID groups BEFORE the install, so the RPM's post-install finds them and does not groupadd its own.
getent group onepassword >/dev/null || groupadd -g "${GID_ONEPASSWORD}" onepassword
getent group onepassword-mcp >/dev/null || groupadd -g "${GID_ONEPASSWORD_MCP}" onepassword-mcp
test "$(getent group onepassword | cut -d: -f3)" = "${GID_ONEPASSWORD}"
test "$(getent group onepassword-mcp | cut -d: -f3)" = "${GID_ONEPASSWORD_MCP}"

# Official repo, package signatures checked (gpgcheck=1). Disabled on disk: bootc images are updated by
# rebuilding, not by dnf on the host. The RPM's post-install rewrites this file with enabled=1; it is
# disabled again below.
cat > /etc/yum.repos.d/1password.repo <<'EOT'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=0
gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOT
rpm --import https://downloads.1password.com/linux/keys/1password.asc
dnf -y --setopt=retries=5 --enablerepo=1password install 1password
sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/1password.repo
grep -qx 'enabled=0' /etc/yum.repos.d/1password.repo
grep -qx 'gpgcheck=1' /etc/yum.repos.d/1password.repo

# /opt/1Password -> /usr/lib/1Password; retarget the symlinks the post-install made into /opt.
test -d /opt/1Password
mv /opt/1Password "${APP_DIR}"
find /usr /etc -lname '/opt/1Password*' -print | while read -r l; do
    ln -snf "$(readlink "$l" | sed "s|^/opt/1Password|${APP_DIR}|")" "$l"
done
cat > /usr/lib/tmpfiles.d/dank-ws-1password.conf <<EOT
# 1Password lives in ${APP_DIR} (image); /opt is /var/opt on bootc. Recreate the path it hardcodes.
L /var/opt/1Password - - - - ${APP_DIR}
EOT

# Modes/ownership as the post-install sets them (mv keeps them; set explicitly so it is visible here):
# chrome-sandbox setuid root (Electron's fallback sandbox), the helpers setgid to their group.
chown root:root "${APP_DIR}/chrome-sandbox"
chmod 4755 "${APP_DIR}/chrome-sandbox"
chown "root:${GID_ONEPASSWORD}" "${APP_DIR}/1Password-BrowserSupport"
chmod 2755 "${APP_DIR}/1Password-BrowserSupport"
if [[ -f "${APP_DIR}/1password-mcp" ]]; then
    chown "root:${GID_ONEPASSWORD_MCP}" "${APP_DIR}/1password-mcp"
    chmod 2755 "${APP_DIR}/1password-mcp"
fi

cat > /usr/lib/sysusers.d/dank-ws-1password.conf <<EOT
# Groups of 1Password's setgid helpers (browser integration, MCP server). Fixed GIDs: the binaries in
# ${APP_DIR} are chgrp'd to these numbers at image build time.
g onepassword     ${GID_ONEPASSWORD}
g onepassword-mcp ${GID_ONEPASSWORD_MCP}
EOT

# Wayland. 1Password 8.12 is built on Electron >= 38, which ignores ELECTRON_OZONE_PLATFORM_HINT (removed
# upstream) and defaults to --ozone-platform=auto, i.e. Wayland only when XDG_SESSION_TYPE=wayland. Pass
# the platform explicitly whenever a Wayland display exists, so it never silently falls back to
# Xwayland (whose clipboard goes through xwayland-satellite). DANK_WS_1PASSWORD_X11=1 forces X11.
rm -f /usr/bin/1password
cat > /usr/bin/1password <<EOT
#!/usr/bin/sh
# dank-ws: start 1Password as a native Wayland app in a Wayland session (see build/1password.sh).
if [ -n "\${WAYLAND_DISPLAY:-}" ] && [ -z "\${DANK_WS_1PASSWORD_X11:-}" ]; then
    exec ${APP_DIR}/1password --ozone-platform=wayland "\$@"
fi
exec ${APP_DIR}/1password "\$@"
EOT
chmod 0755 /usr/bin/1password
for d in /usr/share/applications/com.onepassword.OnePassword.desktop /usr/share/applications/1password.desktop; do
    [[ -f "$d" ]] || continue
    sed -i 's|^Exec=/opt/1Password/1password|Exec=/usr/bin/1password|' "$d"
    chmod 0644 "$d"
done

# Checks: fail the build if any piece is missing.
test -x "${APP_DIR}/1password"
test -x /usr/bin/1password
grep -q "exec ${APP_DIR}/1password --ozone-platform=wayland" /usr/bin/1password
test -u "${APP_DIR}/chrome-sandbox" && test "$(stat -c '%u' "${APP_DIR}/chrome-sandbox")" = 0
test -g "${APP_DIR}/1Password-BrowserSupport"
test "$(stat -c '%g' "${APP_DIR}/1Password-BrowserSupport")" = "${GID_ONEPASSWORD}"
getent group onepassword | grep -q ":${GID_ONEPASSWORD}:"
grep -qx 'Exec=/usr/bin/1password %U' /usr/share/applications/com.onepassword.OnePassword.desktop
if grep -rIl '^Exec=/opt/1Password' /usr/share/applications/; then exit 1; fi
if find /usr /etc -xdev -lname '/opt/1Password*' | grep .; then exit 1; fi
test ! -e /opt/1Password
rpm -q 1password

# Own rechunk component: the whole app dir, the RPM's files outside /opt, and the files written above.
# The rpmdb and /etc/{passwd,group,...} are left alone: the DMS step tags those (dms-state).
{
    find "${APP_DIR}" -type f
    rpm -ql 1password | grep -v '^/opt/'
    find /usr/lib/tmpfiles.d/dank-ws-1password.conf /usr/lib/sysusers.d/dank-ws-1password.conf \
         /usr/bin/1password /etc/yum.repos.d/1password.repo /etc/1password /usr/share/doc/1password \
         /usr/share/polkit-1/actions/com.1password.1Password.policy -type f 2>/dev/null
} | sort -u | while read -r f; do
    if [[ -f "$f" && ! -L "$f" ]]; then setfattr -n user.component -v "${COMPONENT}" "$f"; fi
done
test "$(getfattr --absolute-names -n user.component --only-values "${APP_DIR}/1password")" = "${COMPONENT}"
