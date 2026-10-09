#!/usr/bin/env bash
# Cider (Apple Music client; needs a purchased licence, the repo only distributes packages), both image
# variants. Vendor repo as documented on https://repo.cider.sh/ (same as kmf/getkmf tasks/cider.yml):
# repo id cidercollective, package `Cider`, signatures checked (gpgcheck=1). The repo file stays on disk
# but disabled: bootc images are updated by rebuilding, not by dnf on the host.
#
# The RPM already installs to /usr/lib/Cider (no /opt relocation needed) and has no scriptlets; its
# chrome-sandbox is NOT setuid as packaged (Electron uses unprivileged user namespaces, which EL10
# allows), so modes are left as packaged.
#
# Wayland: Cider 4.x is built on Electron >= 38 (4.0.17: Electron 44), which ignores
# ELECTRON_OZONE_PLATFORM_HINT, so /usr/bin/Cider becomes a wrapper (like /usr/bin/1password) that passes
# --ozone-platform=wayland in a Wayland session. DANK_WS_CIDER_X11=1 forces X11.
set -xeuo pipefail

APP_DIR=/usr/lib/Cider
COMPONENT=cider

rpm -q attr >/dev/null || dnf -y install attr

cat > /etc/yum.repos.d/cider.repo <<'EOT'
[cidercollective]
name=Cider Collective Repository
baseurl=https://repo.cider.sh/rpm/RPMS
enabled=0
gpgcheck=1
gpgkey=https://repo.cider.sh/RPM-GPG-KEY
EOT
rpm --import https://repo.cider.sh/RPM-GPG-KEY
dnf -y --setopt=retries=5 --enablerepo=cidercollective install Cider
grep -qx 'enabled=0' /etc/yum.repos.d/cider.repo
grep -qx 'gpgcheck=1' /etc/yum.repos.d/cider.repo

rm -f /usr/bin/Cider
cat > /usr/bin/Cider <<EOT
#!/usr/bin/sh
# dank-ws: start Cider as a native Wayland app in a Wayland session (see build/cider.sh).
if [ -n "\${WAYLAND_DISPLAY:-}" ] && [ -z "\${DANK_WS_CIDER_X11:-}" ]; then
    exec ${APP_DIR}/Cider --ozone-platform=wayland "\$@"
fi
exec ${APP_DIR}/Cider "\$@"
EOT
chmod 0755 /usr/bin/Cider
sed -i 's|^Exec=Cider\b|Exec=/usr/bin/Cider|' /usr/share/applications/Cider.desktop

# Checks: fail the build if any piece is missing.
rpm -q Cider
test -x "${APP_DIR}/Cider"
test -x /usr/bin/Cider
grep -q "exec ${APP_DIR}/Cider --ozone-platform=wayland" /usr/bin/Cider
grep -qx 'Exec=/usr/bin/Cider %U' /usr/share/applications/Cider.desktop
test -f "${APP_DIR}/resources/app.asar"
if [[ -e /opt/Cider ]]; then echo "Cider unexpectedly installed into /opt" >&2; exit 1; fi

# Own rechunk component (the package's files plus the wrapper and the repo file).
{
    rpm -ql Cider
    echo /usr/bin/Cider
    echo /etc/yum.repos.d/cider.repo
} | sort -u | while read -r f; do
    if [[ -f "$f" && ! -L "$f" ]]; then setfattr -n user.component -v "${COMPONENT}" "$f"; fi
done
test "$(getfattr --absolute-names -n user.component --only-values "${APP_DIR}/Cider")" = "${COMPONENT}"
