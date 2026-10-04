# dank-ws: CentOS Stream 10 bootc image with niri + DankMaterialShell (dms),
# ghostty/kitty, and the dms-greeter/greetd login screen.
#
# Layout follows ublue-os/bluefin-lts: base image + one big RUN with tmpfs
# mounts over /var,/tmp,/boot so the layer carries no stray state.
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
    dnf -y copr enable avengemedia/danklinux && \
    dnf -y copr enable avengemedia/dms-git && \
    dnf -y copr enable kmf/dank-ws-copr && \
    dnf -y copr enable yalter/niri && \
    dnf -y copr enable atim/starship && \
    dnf -y copr enable ublue-os/packages "epel-10-$(arch)" && \
    curl -fsSL --retry 3 -o /etc/yum.repos.d/brave-browser.repo \
        https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo && \
    curl -fsSL --retry 3 -o /etc/yum.repos.d/docker-ce.repo \
        https://download.docker.com/linux/centos/docker-ce.repo && \
    dnf -y install \
        quickshell-git matugen cliphist danksearch dgop dankcalendar-git \
        -x alacritty dms niri ghostty kitty dms-greeter cava kf6-kimageformats && \
    dnf -y install gcc zstd file procps-ng git flatpak starship && \
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
    systemctl enable greetd.service && \
    test -f /usr/lib/systemd/user/dms.service && \
    systemctl --global enable dms.service && \
    systemctl enable brew-setup.service brew-update.timer brew-upgrade.timer && \
    systemctl enable docker.service containerd.service && \
    dnf -y --setopt=retries=5 install uupd && \
    uupd --help 2>&1 | grep -- '--disable-module-distrobox' && \
    sed -i '/^ExecStart=/ s|uupd|& --disable-module-distrobox|' /usr/lib/systemd/system/uupd.service && \
    grep -n '^ExecStart' /usr/lib/systemd/system/uupd.service && \
    systemctl enable uupd.timer && \
    systemctl mask bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service && \
    dnf -y copr disable avengemedia/danklinux && \
    dnf -y copr disable avengemedia/dms-git && \
    dnf -y copr disable kmf/dank-ws-copr && \
    dnf -y copr disable yalter/niri && \
    dnf -y copr disable atim/starship && \
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
    find /etc/skel/.config /etc/niri -type f

# Build-time leftovers: /var/roothome/buildinfo ships in the base image and
# /run/* is written by dnf; bootc lint flags both.
RUN systemctl enable flatpak-preinstall.service && \
    rm -rf /opt /var/roothome/buildinfo /run/rhsm /run/selinux-policy /run/tuned && ln -s /var/opt /opt

LABEL containers.bootc=1
LABEL ostree.bootable=1
LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.vendor="${IMAGE_VENDOR}"
LABEL org.opencontainers.image.description="CentOS Stream 10 bootc image with niri, DankMaterialShell, ghostty and kitty (nvidia variant: ENABLE_NVIDIA=${ENABLE_NVIDIA})"
LABEL org.opencontainers.image.source="${IMAGE_SOURCE}"

RUN bootc container lint --fatal-warnings
