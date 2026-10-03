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
FROM quay.io/centos-bootc/centos-bootc:${BASE_TAG}

ARG IMAGE_NAME="dank-ws"
ARG IMAGE_VENDOR="kmf"
ARG IMAGE_SOURCE=""

# NOTE: /opt is deliberately NOT tmpfs-mounted here (unlike bluefin-lts):
# nothing in this package set installs to /opt, and mounting it would silently
# discard anything that did. If you add a package that installs to /opt, add
# `--mount=type=tmpfs,dst=/opt` and handle its payload explicitly.
RUN --mount=type=tmpfs,dst=/var \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    dnf -y install epel-release dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf -y copr enable avengemedia/danklinux && \
    dnf -y copr enable avengemedia/dms-git && \
    dnf -y copr enable kmf/dank-ws-copr && \
    dnf -y copr enable yalter/niri && \
    dnf -y install \
        quickshell-git matugen cliphist danksearch dgop dankcalendar-git \
        dms niri ghostty kitty dms-greeter cava kf6-kimageformats && \
    systemctl set-default graphical.target && \
    ( if systemctl list-unit-files gdm.service 2>/dev/null | grep -q '^gdm.service'; then \
          systemctl disable gdm.service; \
      fi ) && \
    systemctl enable greetd.service && \
    dnf -y copr disable avengemedia/danklinux && \
    dnf -y copr disable avengemedia/dms-git && \
    dnf -y copr disable kmf/dank-ws-copr && \
    dnf -y copr disable yalter/niri && \
    dnf clean all && \
    find /var -mindepth 1 -delete

# Config files (greetd config, greeter user/cache dir). Copied AFTER the
# package install so our /etc/greetd/config.toml wins over the packaged one.
COPY system_files/ /

RUN rm -rf /opt && ln -s /var/opt /opt

LABEL containers.bootc=1
LABEL ostree.bootable=1
LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.vendor="${IMAGE_VENDOR}"
LABEL org.opencontainers.image.description="CentOS Stream 10 bootc image with niri, DankMaterialShell, ghostty and kitty"
LABEL org.opencontainers.image.source="${IMAGE_SOURCE}"

RUN bootc container lint --fatal-warnings
