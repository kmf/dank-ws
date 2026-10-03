#!/usr/bin/env bash
# NVIDIA variant (dank-ws-nvidia): swap in the ublue-os akmods kernel, install the
# prebuilt kmod-nvidia (open kernel modules) plus negativo17's userspace driver.
# Adapted from ublue-os/bluefin-lts build_scripts/overrides/gdx/20-nvidia.sh and
# build_scripts/scripts/kernel-swap.sh.
#
# Expects (bind-mounted by the Containerfile):
#   /run/akmods/rpms         akmods-nvidia-open rpms (kmods/, ublue-os/)
#   /run/akmods/kernel-rpms  matching kernel rpms
#   /run/build/nvidia_files  files copied verbatim onto /
set -xeuo pipefail

AKMODS=/run/akmods
mkdir -p /var/roothome

dnf -y install 'dnf-command(versionlock)' mokutil

### Kernel swap -------------------------------------------------------------
KERNEL_NAME="kernel"
for pkg in "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" \
           "${KERNEL_NAME}-modules-core" "${KERNEL_NAME}-modules-extra" "${KERNEL_NAME}-uki-virt"; do
    rpm --erase "$pkg" --nodeps || true
done

find "${AKMODS}/kernel-rpms"
CACHED_VERSION="$(cd "${AKMODS}/kernel-rpms" && ls kernel-[0-9]*.rpm | head -1 | sed -E 's/^kernel-//;s/\.rpm$//')"
[[ -n "${CACHED_VERSION}" ]] || { echo "ERROR: no kernel rpm found in ${AKMODS}/kernel-rpms"; exit 1; }
echo "Swapping in kernel ${CACHED_VERSION}"

RPM_NAMES=()
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
           kernel-uki-virt kernel-devel kernel-devel-matched; do
    RPM_NAMES+=("${AKMODS}/kernel-rpms/${pkg}-${CACHED_VERSION}.rpm")
done
dnf -y install "${RPM_NAMES[@]}"

# Keep the kernel in lockstep with the prebuilt kmod
dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
    kernel-devel kernel-devel-matched kernel-uki-virt

### NVIDIA driver -------------------------------------------------------------
KERNEL_VRA="$(rpm -q kernel --queryformat '%{EVR}.%{ARCH}')"
QUALIFIED_KERNEL="$(ls /usr/lib/modules | tail -n 1)"

ARCH="$(uname -m)"
FEDORA_VERSION="${FEDORA_AKMODS_VERSION:-43}"
AKMODS_FEDORA_VERSION="$(find "${AKMODS}/rpms" -name '*.rpm' -print | grep -oPm1 '(?<=\.fc)\d+' | head -n1 || true)"
[[ -z "${AKMODS_FEDORA_VERSION}" ]] || FEDORA_VERSION="${AKMODS_FEDORA_VERSION}"
curl -fsSL --retry 3 "https://negativo17.org/repos/fedora-nvidia.repo" \
    | sed "s/\$releasever/${FEDORA_VERSION}/g" > /etc/yum.repos.d/fedora-nvidia.repo
dnf config-manager --set-disabled fedora-nvidia

dnf -y install --enablerepo=fedora-nvidia \
    "${AKMODS}"/rpms/kmods/kmod-nvidia-"${KERNEL_VRA}"-*.rpm \
    "${AKMODS}"/rpms/ublue-os/*.rpm
dnf config-manager --set-enabled nvidia-container-toolkit

KMOD_VERSION="$(rpm -q --queryformat '%{VERSION}' kmod-nvidia)"
NVIDIA_PKG_VERSION="3:${KMOD_VERSION}"
dnf -y install --enablerepo=fedora-nvidia \
    "libnvidia-fbc-${NVIDIA_PKG_VERSION}" \
    "nvidia-driver-${NVIDIA_PKG_VERSION}" \
    "nvidia-driver-cuda-${NVIDIA_PKG_VERSION}" \
    "nvidia-settings-${NVIDIA_PKG_VERSION}" \
    nvidia-container-toolkit

DRIVER_VERSION="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [[ "${KMOD_VERSION}" != "${DRIVER_VERSION}" ]]; then
    echo "Error: kmod-nvidia (${KMOD_VERSION}) does not match nvidia-driver (${DRIVER_VERSION})"
    exit 1
fi

cat > /usr/lib/modprobe.d/00-nouveau-blacklist.conf <<'EOT'
blacklist nouveau
options nouveau modeset=0
EOT

mkdir -p /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/00-nvidia.toml <<'EOT'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOT

dnf config-manager --set-disabled nvidia-container-toolkit
systemctl enable nvidia-cdi-refresh.path nvidia-cdi-refresh.service
semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp

if [[ -f /etc/modprobe.d/nvidia-modeset.conf ]]; then
    cp /etc/modprobe.d/nvidia-modeset.conf /usr/lib/modprobe.d/nvidia-modeset.conf
fi
# Force the driver into the initramfs (black screen on boot otherwise) and
# preload the iGPU drivers so Chromium-based browsers keep hardware acceleration.
sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf

### Secure Boot: ship the akmods signing cert + enrollment helper -------------
mkdir -p /etc/pki/akmods/certs
if [[ ! -s /etc/pki/akmods/certs/akmods-ublue.der ]]; then
    curl --retry 15 -fLo /etc/pki/akmods/certs/akmods-ublue.der \
        "https://github.com/ublue-os/akmods/raw/main/certs/public_key.der"
fi
cp -av /run/build/nvidia_files/. /
chown root:root /usr/bin/dank-ws-enroll-mok /etc/profile.d/dank-ws-nvidia-mok.sh
chmod 0755 /usr/bin/dank-ws-enroll-mok
chmod 0644 /etc/profile.d/dank-ws-nvidia-mok.sh

### Rebuild the initramfs for the swapped kernel + nvidia -----------------------
/usr/bin/dracut --no-hostonly --kver "${QUALIFIED_KERNEL}" --reproducible --tmpdir /boot \
    --zstd -v --add ostree -f "/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"
