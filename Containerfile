# dank-ws: CentOS Stream 10 bootc image with niri + DankMaterialShell (dms),
# ghostty/kitty, and the dms-greeter/greetd login screen.
#
# Layout follows ublue-os/bluefin-lts: base image + one big RUN with tmpfs
# mounts over /var,/tmp,/boot so the layer carries no stray state.
#
# Clipboard / X11: wl-clipboard (wl-copy, wl-paste) is installed explicitly (before, it only came in
# as a cliphist dependency). DMS keeps its clipboard history itself (dms server, ext-data-control),
# so no `wl-paste --watch cliphist store` watcher is needed. xwayland-satellite gives X11 apps a display
# and bridges their clipboard; niri >= 25.08 spawns it on demand, no config needed. It is not in EPEL 10;
# the EL10 build comes from the third-party COPR ulysg/xwayland-satellite (enabled only during the build).
#
# AppImages: FUSE 2 (`fuse` = setuid /usr/bin/fusermount, `fuse-libs` = libfuse.so.2), as the AppImage
# FUSE wiki asks for on Fedora, plus FUSE 3 (fuse3/fuse3-libs, setuid fusermount3) for newer static
# runtimes. All from CentOS Stream 10 BaseOS; fuse.ko ships with the kernel (CONFIG_FUSE_FS=m, autoloaded
# via the /dev/fuse static node). No `trusted` group: that step is only for openSUSE's permissions.secure,
# EL10 packages fusermount world-executable setuid root.
#
# Hyprland is intentionally NOT installed: kmf/dank-ws-copr ships a rebuilt
# lua 5.5 for it, which conflicts with el10's stock lua-libs 5.4 (needed by
# wireplumber-libs / ibus-libpinyin).

ARG BASE_TAG="c10s"

# Image variants (one Containerfile, two images):
#   dank-ws         ENABLE_NVIDIA=0 (default)  codecs + extra firmware
#   dank-ws-nvidia  ENABLE_NVIDIA=1            the above + proprietary NVIDIA driver
# For the NVIDIA variant also pass
#   --build-arg AKMODS_NVIDIA_IMAGE=ghcr.io/ublue-os/akmods-nvidia-open:centos-10
# which supplies the matching kernel and prebuilt kmod-nvidia rpms. It defaults
# to `scratch` so the base image never pulls it.
ARG ENABLE_NVIDIA="0"
ARG AKMODS_NVIDIA_IMAGE="scratch"

# Homebrew payload + units (brew-setup.service unpacks it on first boot).
# Same source as ublue-os/bluefin-lts; pinned by digest, bump deliberately.
FROM ghcr.io/ublue-os/brew:latest@sha256:cf6388d6edb3a6fad699f06c0ceb3807f8f1368f942b08f8cc6d45ac4fd1cd92 AS brew

FROM ${AKMODS_NVIDIA_IMAGE} AS akmods_nvidia

FROM quay.io/centos-bootc/centos-bootc:${BASE_TAG}

ARG ENABLE_NVIDIA
ARG IMAGE_NAME="dank-ws"
ARG IMAGE_VENDOR="kmf"
ARG IMAGE_SOURCE=""

# Homebrew system files (units, profile.d, limits, /usr/share/homebrew.tar.zst)
COPY --from=brew /system_files /

# NOTE: /opt is deliberately NOT tmpfs-mounted here (unlike bluefin-lts): the
# only package that installs to /opt is brave-origin, and its payload is moved
# to /usr/lib/brave.com explicitly below. Anything else that lands in /opt is
# removed at the end (/opt -> /var/opt on bootc systems).
RUN --mount=type=tmpfs,dst=/var \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    dnf -y install epel-release dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf -y copr enable kmf/dank-ws-copr && \
    dnf -y copr enable yalter/niri && \
    dnf -y copr enable atim/starship && \
    dnf -y copr enable ulysg/xwayland-satellite && \
    dnf -y copr enable ublue-os/packages "epel-10-$(arch)" && \
    curl -fsSL --retry 3 -o /etc/yum.repos.d/brave-browser.repo \
        https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo && \
    curl -fsSL --retry 3 -o /etc/yum.repos.d/docker-ce.repo \
        https://download.docker.com/linux/centos/docker-ce.repo && \
    dnf -y install -x alacritty niri ghostty kitty greetd cava kf6-kimageformats && \
    dnf -y install wl-clipboard xwayland-satellite && \
    test -x /usr/bin/wl-copy && test -x /usr/bin/wl-paste && test -x /usr/bin/xwayland-satellite && \
    dnf -y install gcc zstd file procps-ng git flatpak starship && \
    dnf -y install fuse fuse-libs fuse3 fuse3-libs && \
    test -u /usr/bin/fusermount && test -u /usr/bin/fusermount3 && \
    test -e /usr/lib64/libfuse.so.2 && test -e /usr/lib64/libfuse3.so.3 && \
    dnf -y install brave-origin && \
    rpm -ql brave-origin | head -40 && \
    dnf -y install docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin && \
    ( test -d /opt/brave.com && mv /opt/brave.com /usr/lib/brave.com ) && \
    ( find /usr /etc -lname '/opt/brave.com*' -print | while read -r l; do \
          ln -snf "$(readlink "$l" | sed 's|^/opt/brave.com|/usr/lib/brave.com|')" "$l"; \
      done ) && \
    ( grep -rIl '/opt/brave.com' /usr /etc 2>/dev/null | \
          xargs -r sed -i 's|/opt/brave.com|/usr/lib/brave.com|g' || true ) && \
    dnf config-manager --add-repo=https://negativo17.org/repos/epel-multimedia.repo && \
    dnf config-manager --set-disabled epel-multimedia && \
    dnf -y install --enablerepo=epel-multimedia -x 'PackageKit*' \
        ffmpeg libavcodec @multimedia \
        gstreamer1-plugins-{bad-free,bad-free-libs,good,base} \
        gstreamer1-plugins-ugly gstreamer1-plugin-libav \
        lame lame-libs libjxl ffmpegthumbnailer openh264 x264-libs x265-libs \
        libva-utils libva-intel-media-driver && \
    dnf -y install \
        linux-firmware alsa-sof-firmware alsa-firmware intel-vsc-firmware \
        iwlwifi-dvm-firmware iwlwifi-mvm-firmware iwlegacy-firmware \
        libertas-firmware qcom-firmware microcode_ctl fwupd && \
    dnf -y install \
        NetworkManager-wifi xdg-user-dirs tuned tuned-ppd nautilus \
        vim-enhanced tmux htop btop fastfetch unzip zip \
        google-noto-sans-fonts google-noto-emoji-fonts jetbrains-mono-fonts-all && \
    dnf -y install plymouth plymouth-system-theme && \
    dnf -y install cups cups-filters cups-pk-helper avahi && \
    test -f /usr/share/plymouth/themes/spinner/spinner.plymouth && \
    test -f /usr/share/dbus-1/system-services/org.opensuse.CupsPkHelper.Mechanism.service && \
    systemctl enable cups.socket cups.path avahi-daemon.service && \
    test -f /usr/lib/systemd/system/tuned.service && \
    test -f /usr/lib/systemd/system/tuned-ppd.service && \
    systemctl enable tuned.service tuned-ppd.service && \
    mkdir -p /etc/flatpak/remotes.d && \
    curl -fsSL --retry 3 -o /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://dl.flathub.org/repo/flathub.flatpakrepo && \
    systemctl set-default graphical.target && \
    ( if systemctl list-unit-files gdm.service 2>/dev/null | grep -q '^gdm.service'; then \
          systemctl disable gdm.service; \
      fi ) && \
    systemctl enable brew-setup.service brew-update.timer brew-upgrade.timer && \
    systemctl enable docker.service containerd.service && \
    dnf -y --setopt=retries=5 install uupd && \
    uupd --help 2>&1 | grep -- '--disable-module-distrobox' && \
    sed -i '/^ExecStart=/ s|uupd|& --disable-module-distrobox|' /usr/lib/systemd/system/uupd.service && \
    grep -n '^ExecStart' /usr/lib/systemd/system/uupd.service && \
    systemctl enable uupd.timer && \
    systemctl mask bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service && \
    dnf -y copr disable kmf/dank-ws-copr && \
    dnf -y copr disable yalter/niri && \
    dnf -y copr disable atim/starship && \
    dnf -y copr disable ulysg/xwayland-satellite && \
    dnf -y copr disable ublue-os/packages && \
    sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/brave-browser.repo /etc/yum.repos.d/docker-ce.repo && \
    dnf clean all && \
    find /var -mindepth 1 -delete && \
    rm -rf /run/rhsm /run/selinux-policy

# NVIDIA variant only: swap in the ublue-os akmods kernel and install the
# proprietary NVIDIA driver (see build/nvidia.sh). No-op for the base image.
RUN --mount=type=tmpfs,dst=/var \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=bind,from=akmods_nvidia,src=/,dst=/run/akmods \
    --mount=type=bind,src=build,dst=/run/build \
    if [ "${ENABLE_NVIDIA}" = "1" ]; then \
        /run/build/nvidia.sh && \
        dnf -y install --enablerepo=epel libva-nvidia-driver && \
        dnf clean all && find /var -mindepth 1 -delete && \
        rm -rf /run/rhsm /run/selinux-policy; \
    fi

# Initramfs (both variants): regenerate it once, after every package that ships dracut bits
# (plymouth above, the swapped kernel + NVIDIA driver in the NVIDIA step), so the boot splash and
# the graphical LUKS passphrase prompt work. The dank-ws Plymouth theme (penguin logo, see logo/)
# is copied in first and made the default, so it ends up in the initramfs. See build/initramfs.sh.
# Rechunking puts the initramfs in the shared "unpackaged content + initramfs" layer.
COPY system_files/usr/share/plymouth/themes/dank-ws/ /usr/share/plymouth/themes/dank-ws/
RUN --mount=type=tmpfs,dst=/var \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=bind,src=build,dst=/run/build \
    ENABLE_NVIDIA="${ENABLE_NVIDIA}" /run/build/initramfs.sh && \
    rm -rf /run/rhsm /run/selinux-policy

# DankMaterialShell stack: everything from the avengemedia COPRs, in its own late layer
# AFTER the heavy package/firmware/codec/NVIDIA layers, so a DMS bump only touches this
# step. CI rechunks the image (rpm-ostree build-chunked-oci); the files of the DMS packages
# are tagged with the user.component xattr so each of them gets a dedicated layer instead of
# being packed into shared size-balanced chunks.
#
# DMS_CHANNEL picks the upstream DMS COPR (published as separate image tags, see README):
#   stable   avengemedia/dms      tagged DMS releases + quickshell
#   rolling  avengemedia/dms-git  DMS git snapshots + quickshell-git   (:latest follows this)
# Everything above this step is identical for both channels, so with a shared build cache both
# channels share every layer except the DMS ones. Unpackaged files this step (and the
# `dms setup` step below) writes, e.g. the rpmdb, /etc/passwd and the COPR .repo files, are
# tagged too, so they don't make the big shared "unpackaged content + initramfs" layer differ.
ARG DMS_CHANNEL="rolling"
RUN --mount=type=tmpfs,dst=/var \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    touch /tmp/dms-step-start && \
    case "${DMS_CHANNEL}" in \
        stable)  DMS_COPR=avengemedia/dms;     QUICKSHELL=quickshell ;; \
        rolling) DMS_COPR=avengemedia/dms-git; QUICKSHELL=quickshell-git ;; \
        *) echo "DMS_CHANNEL must be stable or rolling, got '${DMS_CHANNEL}'" >&2; exit 1 ;; \
    esac && \
    dnf -y copr enable avengemedia/danklinux && \
    dnf -y copr enable "${DMS_COPR}" && \
    dnf -y install --enablerepo=epel \
        "${QUICKSHELL}" matugen cliphist danksearch dgop dankcalendar-git dms dms-greeter && \
    rpm -q dms dms-cli "${QUICKSHELL}" && \
    systemctl enable greetd.service && \
    test -f /usr/lib/systemd/user/dms.service && \
    { rpm -q attr >/dev/null || dnf -y install attr; } && \
    for pkg in dms dms-cli "${QUICKSHELL}" matugen cliphist dgop; do \
        rpm -ql "$pkg" | while read -r f; do \
            if [ -f "$f" ] && [ ! -L "$f" ]; then setfattr -n user.component -v "$pkg" "$f"; fi; \
        done; \
        test -n "$(getfattr --absolute-names -n user.component --only-values "$(rpm -ql "$pkg" | while read -r f; do [ -f "$f" ] && [ ! -L "$f" ] && echo "$f" && break; done)")"; \
    done && \
    systemctl --global enable dms.service && \
    dnf -y copr disable avengemedia/danklinux && \
    dnf -y copr disable "${DMS_COPR}" && \
    dnf clean all && \
    find /usr /etc -xdev -type f -newer /tmp/dms-step-start -print0 | \
        xargs -0 -r sh -c 'for f; do getfattr -n user.component "$f" >/dev/null 2>&1 || \
            { setfattr -n user.component -v dms-state "$f" && echo "dms-state: $f"; }; done' sh && \
    getfattr -n user.component --only-values /usr/lib/sysimage/rpm/rpmdb.sqlite | grep -qx dms-state && \
    find /var -mindepth 1 -delete && \
    rm -rf /run/rhsm /run/selinux-policy

# Tailscale, stable channel only (no-op for rolling). Same approach as ublue-os/bluefin-lts:
# Tailscale's own EL repo (tailscale is not in EPEL 10 yet), left on disk but disabled, so updates
# come from rebuilding the image, and tailscaled enabled. Its own step after the DMS layers, so the
# DMS step and everything below it stays cached; the new unpackaged files (the .repo file, rpmdb)
# are tagged with user.component like in the DMS step so they don't end up in the shared layer.
RUN --mount=type=tmpfs,dst=/var \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    if [ "${DMS_CHANNEL}" = "stable" ]; then \
        touch /tmp/tailscale-step-start && \
        dnf config-manager --add-repo "https://pkgs.tailscale.com/stable/centos/10/tailscale.repo" && \
        dnf config-manager --set-disabled tailscale-stable && \
        dnf -y --enablerepo tailscale-stable install tailscale && \
        rpm -q tailscale && \
        test -f /usr/lib/systemd/system/tailscaled.service && \
        systemctl enable tailscaled.service && \
        dnf clean all && \
        find /usr /etc -xdev -type f -newer /tmp/tailscale-step-start -print0 | \
            xargs -0 -r sh -c 'for f; do getfattr -n user.component "$f" >/dev/null 2>&1 || \
                { setfattr -n user.component -v tailscale "$f" && echo "tailscale: $f"; }; done' sh && \
        find /var -mindepth 1 -delete && \
        rm -rf /run/rhsm /run/selinux-policy; \
    fi

# Config files (greetd config, greeter user/cache dir). Copied AFTER the
# package install so our /etc/greetd/config.toml wins over the packaged one.
COPY system_files/ /

# Signature enforcement: installed systems only accept our images when they carry a valid
# cosign signature (public key = cosign.pub, signed by the CI workflow). See build/signing.sh.
COPY cosign.pub /etc/pki/containers/dank-ws.pub
RUN --mount=type=bind,src=build,dst=/run/build \
    /run/build/signing.sh "ghcr.io/${IMAGE_VENDOR}" dank-ws dank-ws-nvidia

# Default niri + DMS config. Generated with the same command users would run
# (`dms setup headless`; it refuses to run as root, hence `nobody`) so it always matches the
# installed dms version: config.kdl with the dms/*.kdl includes (keybinds: Mod+T = kitty,
# Mod+Space = DMS launcher, ...), plus the kitty config. It is used
#   - as /etc/skel/.config for NEW users (the installer's user, `useradd -m`), and
#   - as /etc/niri (niri's system-wide fallback when ~/.config/niri/config.kdl does not exist;
#     without it niri writes its own default which has no DMS keybinds and spawns waybar).
# /etc/dms/cli-policy.json (shipped above) unblocks `dms setup`, which dms otherwise disables
# on ostree/bootc systems.
RUN --mount=type=tmpfs,dst=/tmp \
    install -d -o nobody -g nobody /tmp/skel-home && \
    runuser -u nobody -- env HOME=/tmp/skel-home dms setup headless --compositor niri --terminal kitty && \
    grep -q 'include optional=true "dms/binds.kdl"' /tmp/skel-home/.config/niri/config.kdl && \
    grep -q '"kitty"' /tmp/skel-home/.config/niri/dms/binds.kdl && \
    niri validate -c /tmp/skel-home/.config/niri/config.kdl && \
    install -d /etc/skel/.config /etc/niri && \
    cp -a /tmp/skel-home/.config/. /etc/skel/.config/ && \
    cp -a /tmp/skel-home/.config/niri/. /etc/niri/ && \
    find /etc/skel/.config /etc/niri -type f ! -type l -exec setfattr -n user.component -v dms-config {} + && \
    find /etc/skel/.config /etc/niri -type f

# Build-time leftovers: /var/roothome/buildinfo ships in the base image and
# /run/* is written by dnf (and /run/cups by the cups package); bootc lint flags both.
# fuse.ko check runs here so it covers the kernel the NVIDIA variant swaps in, too.
RUN systemctl enable flatpak-preinstall.service dank-ws-docker-group.service && \
    ( for k in /usr/lib/modules/*/; do \
          { find "$k" -name 'fuse.ko*' | grep -q . || grep -q '/fuse.ko' "$k/modules.builtin"; } || \
          { echo "no fuse kernel module in $k" >&2; exit 1; }; \
      done ) && \
    rm -rf /opt /var/roothome/buildinfo /run/rhsm /run/selinux-policy /run/tuned /run/cups && ln -s /var/opt /opt

LABEL containers.bootc=1
LABEL ostree.bootable=1
LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.vendor="${IMAGE_VENDOR}"
LABEL org.opencontainers.image.description="CentOS Stream 10 bootc image with niri, DankMaterialShell, ghostty and kitty (nvidia variant: ENABLE_NVIDIA=${ENABLE_NVIDIA})"
LABEL org.opencontainers.image.source="${IMAGE_SOURCE}"
LABEL io.github.kmf.dank-ws.dms-channel="${DMS_CHANNEL}"

RUN bootc container lint --fatal-warnings
