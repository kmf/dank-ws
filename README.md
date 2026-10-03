# dank-ws-image

A CentOS Stream 10 [bootc](https://containers.github.io/bootc/) image, modelled on
[bluefin-lts](https://github.com/ublue-os/bluefin-lts), that ships:

- **niri** (compositor) + **DankMaterialShell** (`dms`, `quickshell-git`, `matugen`, `cliphist`, `danksearch`, `dgop`, `dankcalendar-git`)
- **ghostty** and **kitty** terminals
- **dms-greeter** on **greetd** as the login screen (replaces gdm if present)
- `cava`, `kf6-kimageformats`
- **starship** prompt (bash/zsh) with a system-wide default config - see [Starship](#starship)
- **Homebrew** (Linuxbrew, unpacked on first boot), **Bazaar** (Flathub app store, Flatpak),
  **Brave Origin** (browser) and **Docker Engine** (`docker-ce`) - see [Extra components](#extra-components)

Packages come from EPEL/CRB plus the COPRs `avengemedia/danklinux`, `avengemedia/dms-git`,
`yalter/niri`, `atim/starship` (EL10 builds; starship is not in EPEL 10) and [`kmf/dank-ws-copr`](https://github.com/kmf/dank-ws-copr).
The COPR repos are disabled again at the end of the build. Brave's and Docker's yum repos are
left on disk but disabled (`enabled=0`) after install, so updates come from rebuilding the image.

**Hyprland is intentionally not included**: `kmf/dank-ws-copr` ships a rebuilt `lua` 5.5 for it,
which conflicts with el10's stock `lua-libs` 5.4 (needed by `wireplumber-libs`, `ibus-libpinyin`).

## Image variants

One `Containerfile` builds two images (selected by `--build-arg ENABLE_NVIDIA=0|1`):

| Image | Contents |
|---|---|
| `ghcr.io/<owner>/dank-ws` | Everything above + multimedia codecs + extra firmware |
| `ghcr.io/<owner>/dank-ws-nvidia` | `dank-ws` + proprietary NVIDIA driver (open kernel modules) - see [NVIDIA variant](#nvidia-variant-dank-ws-nvidia) |

Each variant has its own interactive install ISO - see [Installer ISO](#installer-iso-live-usb).

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | The image (`ARG BASE_TAG` selects the `centos-bootc` tag, default `c10s`; `ARG ENABLE_NVIDIA` selects the variant) |
| `build/` | `nvidia.sh` (kernel swap + NVIDIA driver, only run when `ENABLE_NVIDIA=1`) and `nvidia_files/` (Secure Boot key enrollment helper) |
| `system_files/` | Copied into `/`: greetd config, greeter + `docker` group sysusers/tmpfiles, `flatpak-preinstall.service`, Bazaar preinstall list |
| `.github/workflows/build.yml` | Matrix-build both images, push to GHCR, sign with cosign (weekly + on push to `main`) |
| `Justfile` | `build`, `build-nvidia`, `build-qcow2`, `build-qcow2-nvidia`, `build-iso`, `build-iso-nvidia`, `check`, `clean` |
| `image.toml` | bootc-image-builder config for the VM disk image (`just build-qcow2`) |
| `iso.toml` | bootc-image-builder config template for the interactive installer ISO (`@IMAGE@` is filled in per variant) |

## Extra components

### Homebrew
System files (units, `profile.d`, limits, and the `/usr/share/homebrew.tar.zst` payload) are copied
from `ghcr.io/ublue-os/brew` (the same image bluefin-lts uses, pinned by digest in the
`Containerfile`). On first boot `brew-setup.service` unpacks Homebrew into `/home/linuxbrew/.linuxbrew`
(owned by uid/gid 1000, i.e. the first user), then touches `/etc/.linuxbrew` so it only runs once.
`brew-update.timer` and `brew-upgrade.timer` are enabled. `gcc`, `zstd`, `file`, `procps-ng` and `git`
are installed because Homebrew needs them.

### Bazaar / Flathub
`flatpak` is installed and the Flathub remote is shipped in `/etc/flatpak/remotes.d/`.
`flatpak-preinstall.service` (enabled) runs `flatpak preinstall` on boot and installs everything listed in
`/usr/share/flatpak/preinstall.d/` - currently [Bazaar](https://github.com/kolunmi/bazaar)
(`io.github.kolunmi.Bazaar`). The service skips itself if `flatpak preinstall` is unavailable.
It needs network access on first boot; add more apps by appending `[Flatpak Preinstall <app-id>]` sections.

### Brave Origin
Installed from Brave's RPM repo (`brave-origin`). The package installs to `/opt/brave.com`, which does
not persist on bootc systems, so the build moves it to `/usr/lib/brave.com` and rewrites the symlinks
and path references; launch with `brave-origin`.

### Docker Engine
`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` and `docker-compose-plugin` from
Docker's CentOS repo; `docker.service` and `containerd.service` are enabled.

- **Licensing:** Docker Engine (Moby) is Apache-2.0 and free to use. Docker Desktop has separate
  (paid for larger companies) terms and is **not** included. This is the published licensing, not legal advice.
- **Group:** the `docker` group exists (sysusers) but no one is added. Adding a user
  (`sudo usermod -aG docker $USER`) grants **root-equivalent** access to the host.
- **Conflicts:** `podman-docker` conflicts with `docker-ce`; do not layer it. Use `podman` directly, or
  Docker, not the compat shim alongside.

### Starship
Installed from the `atim/starship` COPR. `/etc/profile.d/starship.sh` initialises it for interactive
bash/zsh (skipped for `TERM=dumb`/`linux` and when `~/.config/no-starship` exists). Without a
`~/.config/starship.toml` the system default `/etc/starship.toml` (no Nerd Font glyphs required) is used.

### Multimedia codecs (both images)
From [negativo17's `epel-multimedia`](https://negativo17.org/) repo (the same source as bluefin-lts), installed
and then left disabled: `ffmpeg`, `libavcodec`, the `@multimedia` group, `gstreamer1-plugins-ugly`,
`gstreamer1-plugin-libav`, `openh264`, `x264-libs`, `x265-libs`, `lame`, `libjxl`, `ffmpegthumbnailer`,
`libva-utils` and `libva-intel-media-driver`. There is no `mesa-freeworld` equivalent on EL10.

### Extra firmware (both images)
`linux-firmware` and its sub-packages are already in the base image; the build adds `alsa-sof-firmware`,
`alsa-firmware`, `intel-vsc-firmware`, `iwlwifi-dvm/mvm-firmware`, `iwlegacy-firmware`, `libertas-firmware`,
`qcom-firmware`, `microcode_ctl` and `fwupd`.

### NVIDIA variant (`dank-ws-nvidia`)
Follows bluefin-lts' GDX build (`build/nvidia.sh`): the kernel is swapped for the one from
`ghcr.io/ublue-os/akmods-nvidia-open:centos-10` and version-locked, the prebuilt `kmod-nvidia` plus
negativo17's `nvidia-driver`, `nvidia-driver-cuda`, `nvidia-settings`, `libnvidia-fbc`,
`nvidia-container-toolkit` and `libva-nvidia-driver` are installed, nouveau is blacklisted, the kargs
`nvidia-drm.modeset=1 modprobe.blacklist=nouveau rd.driver.blacklist=nouveau` are set via
`/usr/lib/bootc/kargs.d/00-nvidia.toml`, and the initramfs is rebuilt with the driver forced in.

- **Supported GPUs:** the *open* kernel modules (`nvidia-open`) support **GeForce GTX 16-series / RTX
  (Turing) and newer only**. Older cards (Pascal and earlier, e.g. GTX 10-series) are not supported by this image.
- **Secure Boot:** the modules are signed with the ublue-os akmods key, which must be enrolled once.
  The cert is shipped at `/etc/pki/akmods/certs/akmods-ublue.der`. Run `dank-ws-enroll-mok` (wraps
  `mokutil --import /etc/pki/akmods/certs/akmods-ublue.der`), set a one-time password, reboot, and choose
  *Enroll MOK* in the blue screen. A login-shell hint reminds you while Secure Boot is on and the key is not enrolled.
- The kernel is pinned to the akmods build, so kernel updates arrive with image rebuilds only.

### Updates (uupd)
[`uupd`](https://github.com/ublue-os/uupd) (Universal Blue's updater, from the `ublue-os/packages` COPR,
enabled for the install only) updates the OS image (`bootc`), system Flatpaks and Homebrew
(`/home/linuxbrew/.linuxbrew`) in one run. `uupd.timer` is enabled (daily around 04:00, with a random delay
and catch-up after resume), and its service runs with `--disable-module-distrobox` (distrobox is not
shipped). `bootc-fetch-apply-updates.timer`/`.service` are masked so the two updaters do not compete.
Run it by hand with `sudo uupd` (`--dry-run` to preview; `--disable-module-brew|flatpak|system` to skip a
module). A pending OS update is staged and applied on the next reboot (`uupd --apply` reboots).
`brew-update.timer`/`brew-upgrade.timer` from the Homebrew image stay enabled alongside it.

## Per-user setup (runtime, NOT at image build time)

`dms setup headless` writes into `$HOME` (niri config + DMS integration), so it is run once per
user after first login, from a terminal:

```bash
dms setup headless --compositor niri --terminal ghostty --no-systemd --skip-existing
# optional: start DMS via systemd user service instead
systemctl --user enable --now dms
```

## Publish your own build

1. **Generate cosign keys** (use an *empty* password, the workflow sets `COSIGN_PASSWORD=""`):
   ```bash
   cosign generate-key-pair
   ```
   Commit `cosign.pub`. **Never commit `cosign.key`** (it is in `.gitignore`).
2. **Set the secret** `SIGNING_SECRET` to the contents of `cosign.key`:
   ```bash
   gh secret set SIGNING_SECRET < cosign.key
   ```
3. **Publish**: push this repo to GitHub (default branch `main`). The workflow builds on push,
   weekly (Sundays 05:00 UTC) and on manual dispatch, pushes
   `ghcr.io/<owner>/dank-ws:latest` and `ghcr.io/<owner>/dank-ws-nvidia:latest` (+ a `YYYYMMDD` tag each, matrix build) and signs the digests. Pull requests build only.
   After the first push, make the GHCR package public if you want to pull it without credentials.
4. **Switch a host** (any existing bootc system, e.g. CentOS Stream 10 bootc, Fedora bootc, Bluefin LTS):
   ```bash
   sudo bootc switch ghcr.io/<owner>/dank-ws:latest         # or dank-ws-nvidia:latest
   sudo systemctl reboot
   ```
   `<owner>` must be lowercase.

### Optional: enforce signature verification on the installed system

Not enabled by default (the image would need your `cosign.pub` baked in). To enforce: add
`cosign.pub` to the image at `/etc/pki/containers/dank-ws.pub`, add a
`/etc/containers/registries.d/dank-ws.yaml` with `docker: {ghcr.io/<owner>/dank-ws: {use-sigstore-attachments: true}}`,
and a `sigstoreSigned` entry for `ghcr.io/<owner>/dank-ws` in `/etc/containers/policy.json`; then add
`--enforce-container-sigpolicy` to the `bootc switch` in `iso.toml`.

## Local builds

```bash
just build            # sudo podman build -> localhost/dank-ws:latest
just build-nvidia     # NVIDIA variant -> localhost/dank-ws-nvidia:latest
just build-qcow2      # output/qcow2/disk.qcow2 via bootc-image-builder + image.toml
just build-iso        # output/dank-ws/bootiso/install.iso (interactive installer, see below)
just build-iso-nvidia # output/dank-ws-nvidia/bootiso/install.iso
```

Before building a VM image, edit the placeholder user/password in `image.toml`. If you are not `kmf`, set
`ISO_OWNER=<owner>` for the ISO targets (and `IMAGE_VENDOR` in the Containerfile).

## Installer ISO (live USB)

`just build-iso` / `just build-iso-nvidia` build an **interactive Anaconda installer** with
[bootc-image-builder](https://github.com/osbuild/bootc-image-builder) (`--type anaconda-iso`). The ISO
**embeds the image it was built from**, so installing works offline; the kickstart in `iso.toml` only adds a
`%post` step that re-points the installed system at `ghcr.io/<owner>/<image>:latest` (`bootc switch
--mutate-in-place`, no download) so `bootc upgrade` / `uupd` follow the published image from then on.
That means the image must exist on GHCR (public) for updates to work; the switch does **not** enforce a
signature policy (see [enforce signature verification](#optional-enforce-signature-verification-on-the-installed-system)).

bootc-image-builder only injects the `ostreecontainer` kickstart command. Because `iso.toml` contains no
`autopart`/`clearpart`/`user`/`text --non-interactive` lines, Anaconda asks for everything on the target
machine: language, keyboard, time zone, **Installation Destination** (automatic or custom partitioning, with
the **"Encrypt my data" (LUKS2) checkbox** and a passphrase prompt), network and **user creation**. The
Storage, Users, Network, Localization and Timezone Anaconda modules are enabled in `iso.toml` (`disable`
overrides `enable`, so never list them under `disable`).

```bash
just build-iso            # or: just build-iso-nvidia   (needs sudo/rootful podman, ~15 GB free disk)
ls -lh output/dank-ws/bootiso/install.iso      # ~4 GB (dank-ws-nvidia: ~5 GB)
```

ISOs are 4-5 GB, above GitHub's 2 GiB release-asset limit and awkward as workflow artifacts on the free
runners, so they are **built locally** (the CI workflow above is manual) and published on the
[`v0.1.0-iso` release](https://github.com/kmf/dank-ws/releases/tag/v0.1.0-iso) as split parts.

### Building the ISO in CI (manual)

The **Build installer ISO** workflow (`.github/workflows/build-iso.yml`, `workflow_dispatch` only) pulls
`ghcr.io/<owner>/<variant>:<tag>` and runs the same bootc-image-builder step as the Justfile on a free
`ubuntu-24.04` runner (about 11 minutes for dank-ws). Inputs: `variant` (`dank-ws`, `dank-ws-nvidia` or
`both`, one matrix job each), `tag`, `publish_release` and `release_tag`. The ISO and its checksum are
uploaded as an Actions artifact (kept 14 days, stored uncompressed). With `publish_release` the ISO is
split into 1900M parts and attached to the release (created as a prerelease if missing):

```bash
gh workflow run build-iso.yml -f variant=both -f publish_release=true -f release_tag=v0.2.0-iso
```

### Downloading a prebuilt ISO

Each ISO is split into <2 GiB parts (`split -b 1900M`). Download all parts of the variant you want plus
`SHA256SUMS` from the release, then reassemble and verify:

```bash
cat dank-ws-install.iso.part* > dank-ws-install.iso                    # or dank-ws-nvidia-install.iso.part*
sha256sum -c SHA256SUMS --ignore-missing
# or with the GitHub CLI:
gh release download v0.1.0-iso -R kmf/dank-ws -p 'dank-ws-install.iso.part*' -p SHA256SUMS
```

`SHA256SUMS.parts` holds the checksums of the individual parts. The prebuilt ISOs were only tested in
QEMU/UEFI.

### Writing the USB stick

```bash
# DESTRUCTIVE: replace /dev/sdX with the USB stick (check with lsblk!)
sudo dd if=output/dank-ws/bootiso/install.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

(or Fedora Media Writer / `gnome-disk-utility` "Restore Disk Image"). Boot it in UEFI mode.

### Using the installer / disk encryption

1. Choose language, keyboard and time zone, and confirm them (the hub shows warnings until each spoke is visited).
2. **Installation Destination**: select the disk, tick **Encrypt my data**, press *Done* and enter the LUKS
   passphrase. The default layout is an EFI partition, an XFS `/boot` and one LUKS2 partition holding LVM
   (root + swap). Choose *Custom* for your own layout.
3. **User Creation** (tick *administrator* to get `sudo`); the root account stays disabled unless you set it.
4. *Begin Installation*, reboot, and enter the LUKS passphrase at the boot prompt.

On boot dracut may print `Failed to start systemd-cryptsetup@luks-... Unit ... not found`; this is a harmless
duplicate unlock attempt in the initramfs - the passphrase prompt follows and the boot continues.

**Optional follow-up (untested here): TPM2 auto-unlock.** After the first boot you can add a TPM2 key slot
with `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/<LUKS-UUID>` and pass
`rd.luks.options=<LUKS-UUID>=tpm2-device=auto` as a kernel argument; keep the passphrase as the recovery key.
PCR 7 binds to the Secure Boot state, so re-enroll after changing Secure Boot keys.

**NVIDIA ISO + Secure Boot:** the installer boots under Secure Boot (shim), but the installed
`dank-ws-nvidia` system needs the akmods key enrolled once - run `dank-ws-enroll-mok` after the first boot
(see [NVIDIA variant](#nvidia-variant-dank-ws-nvidia)).

## Status / caveats

- The image builds with podman on CentOS Stream 10 and passes `bootc container lint --fatal-warnings`.
  It boots in QEMU/UEFI to the dms-greeter login screen **when the VM has 3D acceleration**
  (virtio-gpu with virgl). niri refuses software-only EGL renderers (llvmpipe/`kms_swrast`), so on a
  VM without 3D (e.g. the stock RHEL/CentOS `qemu-kvm`, which has no `virtio-vga-gl`) the greeter shows a
  black screen although greetd, niri and quickshell are all running. Real GPUs are fine.
- greetd/greeter details to verify on first boot: `getent passwd greeter`, `/var/cache/dms-greeter`
  ownership, `systemctl status greetd`. If the `greetd` package from `kmf/dank-ws-copr` uses a
  different default user (its spec rewrites `greeter` to `greetd`), keep `user =` in
  `system_files/etc/greetd/config.toml` consistent with the account that exists.
- Only `linux/amd64` is built by the workflow; add an arm64 runner matrix only after checking that
  every COPR has aarch64 builds.
