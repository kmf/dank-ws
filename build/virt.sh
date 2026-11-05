#!/usr/bin/env bash
# Virtualization: libvirt (modular daemons) + QEMU/KVM, all from CentOS Stream 10 AppStream.
# virt-manager is not packaged for EL10 (neither AppStream nor EPEL 10); use the Flathub build
# (org.virt_manager.virt-manager) or `virt-install`/`virsh` instead.
set -xeuo pipefail

case "$(arch)" in
    x86_64)  fw=edk2-ovmf ;;
    aarch64) fw=edk2-aarch64 ;;
    *) echo "unsupported arch $(arch)" >&2; exit 1 ;;
esac

dnf -y install \
    libvirt-daemon-kvm libvirt-client libvirt-nss \
    qemu-kvm virt-install virt-viewer \
    swtpm swtpm-tools "${fw}"

# Modular daemons, socket-activated (EL10 default; no monolithic libvirtd).
socks="virtqemud.socket virtqemud-ro.socket virtqemud-admin.socket
       virtnetworkd.socket virtnetworkd-ro.socket virtnetworkd-admin.socket
       virtstoraged.socket virtstoraged-ro.socket virtstoraged-admin.socket
       virtnodedevd.socket virtnodedevd-ro.socket virtnodedevd-admin.socket
       virtsecretd.socket virtsecretd-ro.socket virtsecretd-admin.socket
       virtinterfaced.socket virtinterfaced-ro.socket virtinterfaced-admin.socket
       virtnwfilterd.socket virtnwfilterd-ro.socket virtnwfilterd-admin.socket
       virtproxyd.socket virtproxyd-ro.socket virtproxyd-admin.socket
       virtlogd.socket virtlockd.socket"
present=""
for s in $socks; do
    [ -e "/usr/lib/systemd/system/$s" ] && present="$present $s"
done
{
    echo "# dux-ws: libvirt modular daemons (socket-activated)"
    for s in $present; do echo "enable $s"; done
} > /usr/lib/systemd/system-preset/70-dux-ws-libvirt.preset
# shellcheck disable=SC2086
systemctl enable $present
systemctl is-enabled virtqemud.socket virtnetworkd.socket virtstoraged.socket

test -x /usr/libexec/qemu-kvm
command -v virsh virt-install swtpm
rpm -q "${fw}" libvirt-nss
