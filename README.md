<p align="center">
  <img src="logo/penguin-full-256.png" alt="dank-ws penguin logo" width="256" height="256">
</p>

# dank-ws-image

A CentOS Stream 10 [bootc](https://containers.github.io/bootc/) image, modelled on
[bluefin-lts](https://github.com/ublue-os/bluefin-lts), that ships:

- **niri** (compositor) + **DankMaterialShell** (`dms`, `quickshell` or `quickshell-git`, `matugen`, `cliphist`, `danksearch`, `dgop`, `dankcalendar-git`),
  in a stable or rolling flavour - see [Choosing a DMS channel](#choosing-a-dms-channel)
- **ghostty** and **kitty** terminals
- **dms-greeter** on **greetd** as the login screen (replaces gdm if present)
- `cava`, `kf6-kimageformats`
- **Clipboard / X11 apps**: `wl-clipboard` (`wl-copy`, `wl-paste`; DMS keeps the clipboard history itself, `Mod+V`)
  and `xwayland-satellite` (+ Xwayland), which niri starts on demand so X11 apps run and share the clipboard
- **AppImages**: FUSE 2 (`fuse`, `fuse-libs`: `libfuse.so.2` and setuid `fusermount`) as the
  [AppImage FUSE docs](https://github.com/AppImage/AppImageKit/wiki/FUSE) require, plus FUSE 3 (`fuse3`) - AppImages
  run directly (`chmod +x` and start them), no extra group membership needed
- **Printing**: CUPS (`cups`, `cups-filters`, `avahi` for network printer discovery) and `cups-pk-helper`, so printers
  can be added and configured from the DMS settings (polkit-authorized, no root shell needed)
- **Fingerprint login**: `fprintd`/`fprintd-pam` with authselect `with-fingerprint` (sudo, polkit, greeter; password as
  fallback). Enroll with `fprintd-enroll`; for the lock screen also enable it in DMS Settings -> Lock Screen
- **Plymouth** graphical boot splash with the dank-ws penguin logo (see [`logo/`](logo/)) and a graphical LUKS
  passphrase prompt - see [Boot splash](#boot-splash-plymouth)
- **starship** prompt (bash/zsh) with a system-wide default config - see [Starship](#starship)
- **1Password** desktop app (official RPM, native Wayland; in `/usr/lib/1Password`, `/opt/1Password` is a symlink)
  instead of the Flatpak, whose clipboard does not work on niri - see [`build/1password.sh`](build/1password.sh)
- **Fonts**: JetBrains Mono, Fira Code, Fira Mono, Inconsolata, Geist, Geist Mono and the CodeNewRoman, CaskaydiaCove and
  CaskaydiaMono Nerd Fonts - see [`build/fonts.sh`](build/fonts.sh)
- **Homebrew** (Linuxbrew, unpacked on first boot), **Bazaar** (Flathub app store, Flatpak),
  **Brave Origin** (browser) and **Docker Engine** (`docker-ce`) - see [Extra components](#extra-components)

Packages come from EPEL/CRB plus the COPRs `avengemedia/danklinux`, `avengemedia/dms` or `avengemedia/dms-git`,
`yalter/niri`, `atim/starship` (EL10 builds; starship is not in EPEL 10), `ulysg/xwayland-satellite` (EL10 build; not in EPEL 10) and [`kmf/dank-ws-copr`](https://github.com/kmf/dank-ws-copr).
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

## Choosing a DMS channel

Each image is published in two DMS channels (`--build-arg DMS_CHANNEL=stable|rolling`):

| Tag | DMS from | Notes |
|---|---|---|
| `:stable` | `avengemedia/dms` (tagged DMS releases) + `quickshell` | also includes **Tailscale** (`tailscaled` enabled) |
| `:rolling` | `avengemedia/dms-git` (git snapshots) + `quickshell-git` | newest features, can break |
| `:latest` | same image as `:rolling` | kept for systems installed from older ISOs, which track it; current ISOs install `:stable` |

Everything else in the image is identical, except that `:stable` also ships [Tailscale](https://tailscale.com)
from Tailscale's own CentOS 10 repo (as Bluefin LTS does; the repo is left on disk but disabled), with
`tailscaled.service` enabled. Run `sudo tailscale up` to log in. Switch with:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/kmf/dank-ws:rolling          # or :stable
sudo bootc switch --enforce-container-sigpolicy ghcr.io/kmf/dank-ws-nvidia:rolling   # or :stable
sudo systemctl reboot
```

Only the DMS (and, for `:stable`, Tailscale) layers are downloaded (the rest is shared between the channels), and the switch takes
effect after the reboot. Updates then follow the chosen tag. To undo, `sudo bootc rollback` and reboot,
or switch back to the other tag (or `:latest`) the same way.

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | The image (`ARG BASE_TAG` selects the `centos-bootc` tag, default `c10s`; `ARG ENABLE_NVIDIA` selects the variant; `ARG DMS_CHANNEL` selects `stable` or `rolling` DMS, default `rolling`) |
| `build/` | `nvidia.sh` (kernel swap + NVIDIA driver, only run when `ENABLE_NVIDIA=1`), `nvidia_files/` (Secure Boot key enrollment helper) and `initramfs.sh` (initramfs regeneration with plymouth + crypt, both variants) |
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
- **Group:** the `docker` group exists (sysusers) and `dank-ws-docker-group.service`
  adds the first user (UID 1000, created by the installer) to it on boot (idempotent;
  log out and back in to apply). Membership is **root-equivalent** access to the host;
  other users need `sudo usermod -aG docker <user>`.
- **Conflicts:** `podman-docker` conflicts with `docker-ce`; do not layer it. Use `podman` directly, or
  Docker, not the compat shim alongside.

### Starship
Installed from the `atim/starship` COPR. `/etc/profile.d/starship.sh` initialises it for interactive
bash/zsh (skipped for `TERM=dumb`/`linux` and when `~/.config/no-starship` exists). Without a
`~/.config/starship.toml` the system default `/etc/starship.toml` (no Nerd Font glyphs required) is used.

### Boot splash (Plymouth)

`plymouth` + `plymouth-system-theme` are installed (as in Bluefin LTS) and the default theme is `dank-ws`
(`system_files/usr/share/plymouth/themes/dank-ws/`): the dank-ws penguin (`watermark.png` =
`logo/penguin-full-256.png`) on a dark background, with the stock spinner theme's throbber and password dialog
(two-step plugin). The initramfs is regenerated with the `plymouth` and `crypt` dracut modules and the theme
(`build/initramfs.sh`; the build fails if any of them, or the logo, is missing from the initramfs) and `/usr/lib/bootc/kargs.d/10-dank-ws-splash.toml` adds the kernel arguments `rhgb quiet`. So the
LUKS passphrase is asked for on the graphical splash instead of a text prompt. bootc applies kargs.d
changes as a diff, so existing installs get the arguments with the next `bootc upgrade` (or `uupd`) plus a
reboot; nothing else is needed. Press `Esc` during boot to see the boot messages. On `dank-ws-nvidia` the
splash runs on the NVIDIA driver, which is forced into the initramfs with `nvidia-drm.modeset=1`.

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

### How updates flow (end to end)

1. **GitHub Actions builds the images**: weekly (Sunday 05:00 UTC, picks up base image and COPR updates) and on every push to `main`.
2. Each build is pushed to `ghcr.io/kmf/dank-ws` / `ghcr.io/kmf/dank-ws-nvidia` (`:stable`, `:rolling` and `:latest` = rolling, each with a dated tag: `stable-YYYYMMDD`, `rolling-YYYYMMDD`, `YYYYMMDD`) and **signed with cosign** (`SIGNING_SECRET`).
3. The laptop's **`uupd.timer`** (daily) pulls the tag it tracks (`:stable` for installs from current ISOs, `:latest` = rolling for installs from older ISOs, or whatever you switched to), stages the new deployment, and updates Flatpaks and Homebrew too. **Reboot to apply** the staged OS update (`sudo uupd --apply` reboots for you).
4. The installed system **only accepts signed images** for these two repositories (see below), so a tampered or unsigned image is rejected at pull time.

```bash
bootc status             # booted / staged / rollback images and digests
sudo uupd                # update everything now (--dry-run to preview)
sudo bootc upgrade       # OS image only (staged; reboot to apply)
sudo bootc rollback      # boot the previous deployment on the next reboot
```

**Scheduled workflows get disabled by GitHub after 60 days without repository activity** (public repos). If that
happens the weekly build silently stops: re-enable it on the repo's *Actions* tab (*Build and publish image* ->
*Enable workflow*), or run `gh workflow enable build.yml -R kmf/dank-ws` and `gh workflow run build.yml -R kmf/dank-ws`.
Any push to `main` also keeps it alive; check `gh run list -R kmf/dank-ws -w build.yml -L3` now and then.

#### Signature enforcement (installed systems)
`build/signing.sh` runs at image build time and ships, like Bluefin's `ublue-os-signing`:
`/etc/pki/containers/dank-ws.pub` (this repo's `cosign.pub`), `/etc/containers/registries.d/dank-ws.yaml`
(`use-sigstore-attachments: true` for `ghcr.io/kmf`) and `/etc/containers/policy.json` (the distro default
plus `sigstoreSigned` entries for `ghcr.io/kmf/dank-ws` and `ghcr.io/kmf/dank-ws-nvidia`, `signedIdentity: matchRepository`).
Other registries keep the distro default policy. Forks: build with `--build-arg IMAGE_VENDOR=<owner>` and your own `cosign.pub`.
`bootc switch --enforce-container-sigpolicy` (used in `iso.toml`) makes bootc itself apply this policy.
Verify manually: `cosign verify --key cosign.pub ghcr.io/kmf/dank-ws:latest`.

### Updates (uupd)
[`uupd`](https://github.com/ublue-os/uupd) (Universal Blue's updater, from the `ublue-os/packages` COPR,
enabled for the install only) updates the OS image (`bootc`), system Flatpaks and Homebrew
(`/home/linuxbrew/.linuxbrew`) in one run. `uupd.timer` is enabled (daily around 04:00, with a random delay
and catch-up after resume), and its service runs with `--disable-module-distrobox` (distrobox is not
shipped). `bootc-fetch-apply-updates.timer`/`.service` are masked so the two updaters do not compete.
Run it by hand with `sudo uupd` (`--dry-run` to preview; `--disable-module-brew|flatpak|system` to skip a
module). A pending OS update is staged and applied on the next reboot (`uupd --apply` reboots).
`brew-update.timer`/`brew-upgrade.timer` from the Homebrew image stay enabled alongside it.

## First login: DMS autostart, keybinds and default terminal

- **DMS starts by itself.** `dms.service` (the user unit shipped by the `dms` package) is enabled for every user
  (`systemctl --global enable dms.service`); `niri-session` brings up `graphical-session.target`, which starts it.
  Check with `systemctl --user status dms`.
- **Keybinds and defaults come from the niri config.** `config.kdl` includes `dms/*.kdl` (DMS keybinds such as
  `Mod+Space` launcher, `Mod+T` terminal = **kitty**, `Mod+V` clipboard, ...). It is generated at image build time
  with `dms setup headless --compositor niri --terminal kitty` and shipped in `/etc/skel/.config` (new users, e.g.
  the user created by the installer) and in `/etc/niri` (niri's system-wide fallback if a user has no
  `~/.config/niri/config.kdl`). `alacritty` is excluded from the image; `/etc/xdg/xdg-terminals.list` names kitty.
- `dms setup` is blocked on ostree/bootc systems by default; `/etc/dms/cli-policy.json` re-allows it (only
  `dms greeter install|enable|uninstall` stay blocked, the greeter is baked into the image).

**Existing users** (created before this config was in the image) already have a niri-generated
`~/.config/niri/config.kdl` without the DMS includes. Back it up and adopt the image default:

```bash
mv ~/.config/niri ~/.config/niri.bak-$(date +%F)
cp -a /etc/skel/.config/niri ~/.config/niri
mkdir -p ~/.config/kitty && cp -an /etc/skel/.config/kitty/. ~/.config/kitty/
systemctl --user restart dms     # niri live-reloads the config on its own
```

(Or `dms setup headless --compositor niri --terminal kitty --force`, which backs up the old config itself.)
Do not add `--no-systemd`: that variant adds `spawn-at-startup "dms" "run"`, which would start DMS twice.

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
   `ghcr.io/<owner>/dank-ws` and `ghcr.io/<owner>/dank-ws-nvidia` as `:stable`, `:rolling` and `:latest` (= rolling), plus dated tags (matrix build per variant, both channels per job) and signs the digests. Pull requests build only.
   After the first push, make the GHCR package public if you want to pull it without credentials.
4. **Switch a host** (any existing bootc system, e.g. CentOS Stream 10 bootc, Fedora bootc, Bluefin LTS):
   ```bash
   sudo bootc switch ghcr.io/<owner>/dank-ws:latest         # or dank-ws-nvidia:latest
   sudo systemctl reboot
   ```
   `<owner>` must be lowercase.

### Signature verification on the installed system

Enabled by default in the image, see [Signature enforcement](#signature-enforcement-installed-systems).

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
`%post` step that re-points the installed system at `ghcr.io/<owner>/<image>:stable` (`bootc switch
--mutate-in-place`, no download) so `bootc upgrade` / `uupd` follow the published image from then on.
The ISOs embed and track the `:stable` DMS channel (`ISO_CHANNEL` in the Justfile, `tag`/`origin_tag` in the
workflow); systems installed from ISOs built before that track `:latest` (= `:rolling`), which is still published.
Either can move to the other channel with `bootc switch` (see [Choosing a DMS channel](#choosing-a-dms-channel)).
That means the image must exist on GHCR (public) for updates to work. The switch uses
`--enforce-container-sigpolicy`, so later updates are verified against the cosign policy shipped in the image
(see [Signature enforcement](#signature-enforcement-installed-systems)). An ISO only carries that policy if the
image it embeds was built after the policy was added, so rebuild the ISOs after image changes you want installed
fresh (updates after install pull the current image anyway).

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

ISOs are 4-5 GB, above GitHub's 2 GiB release-asset limit, so release assets are split parts. The
published ones were **built locally** (CI is manual only, see below) and are on the
[`v0.1.0-iso` release](https://github.com/kmf/dank-ws/releases/tag/v0.1.0-iso) as split parts.

### Installer branding (why the ISO still says CentOS Stream)

The `anaconda-iso` type of bootc-image-builder has **no branding knobs**. Its config only accepts
`customizations.installer` (kickstart, modules, `bootloader.grub2.menu-timeout`), `user`, `group`, `fips` and
`kernel.append`; `[customizations.iso]` (`volume_id` etc.) is rejected for this type. The rest is derived:

| What | Where it comes from | Result today |
|---|---|---|
| Boot menu entries (`Install ... `, `Test this media & install ...`) | osbuild's fixed grub2 template, filled with `NAME`/`VERSION_ID` from the image's `/usr/lib/os-release` | `Install CentOS Stream 10` |
| Boot menu background/theme | none (plain text grub2 menu, BIOS and UEFI; no isolinux on EL10) | - |
| Anaconda product name (top bar, welcome screen) | `.buildstamp`, same `NAME`/`VERSION_ID` | `CENTOS STREAM 10 INSTALLATION` |
| Anaconda sidebar/top bar logos | `centos-logos`, installed into the installer from the CentOS repos built into bootc-image-builder (not from our image) | CentOS logos |
| ISO volume label | derived from os-release `ID`/`VERSION_ID` | `CentOS-Stream-10-BaseOS-x86_64` |

Putting the dank-ws penguin there means either changing `NAME` in the image's os-release (changes the
product name everywhere, not just in the installer) or post-processing the finished ISO (adding an
Anaconda `images/product.img` with the logos and rewriting `grub.cfg` on the ISO and in its EFI boot
image with `xorriso`). Neither is done yet.

### Building the ISO in CI (manual)

The **Build installer ISO** workflow (`.github/workflows/build-iso.yml`, `workflow_dispatch` only) pulls
`ghcr.io/<owner>/<variant>:<tag>` and runs the same bootc-image-builder step as the Justfile on a free
`ubuntu-24.04` runner (about 11 minutes for dank-ws). Inputs: `variant` (`dank-ws`, `dank-ws-nvidia` or
`both`, one matrix job each), `tag` (image to embed, default `stable`), `origin_tag` (tag the installed system
follows, default `stable`), `publish_release` and `release_tag`. The ISO and its checksum are
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
4. *Begin Installation*, reboot, and enter the LUKS passphrase at the (graphical, Plymouth) boot prompt.

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
