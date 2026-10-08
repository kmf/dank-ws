#!/usr/bin/env bash
# Regenerate the initramfs (both image variants), adapted from ublue-os/bluefin-lts
# build_scripts/26-packages-post.sh. Runs after the package layer and the NVIDIA step, so it picks up
#   - plymouth (graphical boot splash, as in Bluefin LTS) with the dank-ws theme: the dank-ws penguin
#     logo on a dark background plus the spinner theme's throbber and password dialog. It also makes
#     the LUKS passphrase prompt graphical (with the `rhgb` karg, see
#     system_files/usr/lib/bootc/kargs.d/10-dank-ws-splash.toml),
#   - on dank-ws-nvidia: the swapped akmods kernel and the NVIDIA driver (forced in by
#     /usr/lib/dracut/dracut.conf.d/99-nvidia.conf, see nvidia.sh).
# Then checks the result: no silent loss of LUKS unlocking or of the splash.
set -xeuo pipefail

# dracut-install follows the /root -> /var/roothome symlink; /var is a tmpfs during the build
mkdir -p /var/roothome

# Shipped in the image so a local regeneration behaves the same. The modules are normally picked up
# anyway in --no-hostonly mode; listing them makes a missing dependency fail loudly instead.
cat > /usr/lib/dracut/dracut.conf.d/50-dank-ws.conf <<'EOT'
# dank-ws: graphical boot splash (also renders the LUKS passphrase prompt) and LUKS unlocking
add_dracutmodules+=" plymouth crypt "
EOT

# dank-ws Plymouth theme (.plymouth + watermark.png copied in by the Containerfile): take the
# throbber / password dialog images from the stock spinner theme and make it the default theme
# (/etc/plymouth/plymouthd.conf, read by plymouth-populate-initrd and by plymouthd).
THEME_DIR=/usr/share/plymouth/themes/dank-ws
test -f "${THEME_DIR}/dank-ws.plymouth" && test -f "${THEME_DIR}/watermark.png"
for img in /usr/share/plymouth/themes/spinner/*.png; do
    [[ "$(basename "${img}")" == watermark.png ]] || cp "${img}" "${THEME_DIR}/"
done
test -f "${THEME_DIR}/throbber-0001.png" && test -f "${THEME_DIR}/lock.png"
plymouth-set-default-theme dank-ws
[[ "$(plymouth-set-default-theme)" == dank-ws ]]

mapfile -t KVERS < <(find /usr/lib/modules -mindepth 2 -maxdepth 2 -name vmlinuz -printf '%h\n' | xargs -n1 basename | sort -V)
[[ ${#KVERS[@]} -eq 1 ]] || { echo "ERROR: expected exactly one kernel, found: ${KVERS[*]}"; exit 1; }
KVER="${KVERS[0]}"
INITRAMFS="/usr/lib/modules/${KVER}/initramfs.img"
echo "Regenerating ${INITRAMFS}"

/usr/bin/dracut --no-hostonly --kver "${KVER}" --reproducible --tmpdir /boot \
    --zstd --add ostree -f "${INITRAMFS}"

# Sanity checks on the new initramfs
lsinitrd -m "${INITRAMFS}" > /tmp/dracut-modules
for mod in plymouth crypt drm ostree; do
    grep -qx "${mod}" /tmp/dracut-modules || { echo "ERROR: dracut module ${mod} missing from initramfs"; cat /tmp/dracut-modules; exit 1; }
done
lsinitrd "${INITRAMFS}" > /tmp/initramfs-files
for f in 'usr/s?bin/plymouthd' 'usr/(bin|lib/systemd)/systemd-cryptsetup' \
         'usr/share/plymouth/themes/dank-ws/dank-ws\.plymouth' 'usr/share/plymouth/themes/dank-ws/watermark\.png' \
         'usr/share/plymouth/themes/dank-ws/throbber-0001\.png' 'usr/lib64/plymouth/two-step\.so'; do
    grep -Eq " ${f}( ->.*)?\$" /tmp/initramfs-files || { echo "ERROR: ${f} missing from initramfs"; exit 1; }
done
lsinitrd -f etc/plymouth/plymouthd.conf "${INITRAMFS}" > /tmp/initramfs-plymouthd.conf
grep -qx 'Theme=dank-ws' /tmp/initramfs-plymouthd.conf || {
    echo "ERROR: initramfs plymouthd.conf does not select the dank-ws theme"; cat /tmp/initramfs-plymouthd.conf; exit 1; }
lsinitrd -f usr/share/plymouth/themes/dank-ws/watermark.png "${INITRAMFS}" > /tmp/initramfs-watermark.png
cmp /tmp/initramfs-watermark.png "${THEME_DIR}/watermark.png"
grep -E 'plymouth|cryptsetup|nvidia-drm|watermark' /tmp/initramfs-files
if [[ "${ENABLE_NVIDIA:-0}" == "1" ]]; then
    grep -Eq '/nvidia-drm\.ko' /tmp/initramfs-files || { echo "ERROR: nvidia-drm missing from initramfs"; exit 1; }
fi
ls -l "${INITRAMFS}"
