# dank-ws-image

A CentOS Stream 10 [bootc](https://containers.github.io/bootc/) image, modelled on
[bluefin-lts](https://github.com/ublue-os/bluefin-lts), that ships:

- **niri** (compositor) + **DankMaterialShell** (`dms`, `quickshell-git`, `matugen`, `cliphist`, `danksearch`, `dgop`, `dankcalendar-git`)
- **ghostty** and **kitty** terminals
- **dms-greeter** on **greetd** as the login screen (replaces gdm if present)
- `cava`, `kf6-kimageformats`
- **Homebrew** (Linuxbrew, unpacked on first boot), **Bazaar** (Flathub app store, Flatpak),
  **Brave Origin** (browser) and **Docker Engine** (`docker-ce`) - see [Extra components](#extra-components)

Packages come from EPEL/CRB plus the COPRs `avengemedia/danklinux`, `avengemedia/dms-git`,
`yalter/niri` and [`kmf/dank-ws-copr`](https://github.com/kmf/dank-ws-copr).
The COPR repos are disabled again at the end of the build. Brave's and Docker's yum repos are
left on disk but disabled (`enabled=0`) after install, so updates come from rebuilding the image.

**Hyprland is intentionally not included**: `kmf/dank-ws-copr` ships a rebuilt `lua` 5.5 for it,
which conflicts with el10's stock `lua-libs` 5.4 (needed by `wireplumber-libs`, `ibus-libpinyin`).

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | The image (`ARG BASE_TAG` selects the `centos-bootc` tag, default `c10s`) |
| `system_files/` | Copied into `/`: greetd config, greeter + `docker` group sysusers/tmpfiles, `flatpak-preinstall.service`, Bazaar preinstall list |
| `.github/workflows/build.yml` | Build, push to GHCR, sign with cosign (weekly + on push to `main`) |
| `Justfile` | `build`, `build-qcow2`, `build-iso`, `check`, `clean` |
| `image.toml` / `iso.toml` | bootc-image-builder configs (VM disk / installer ISO) |

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
   `ghcr.io/<owner>/dank-ws:latest` (+ a `YYYYMMDD` tag) and signs the digest. Pull requests build only.
   After the first push, make the GHCR package public if you want to pull it without credentials.
4. **Switch a host** (any existing bootc system, e.g. CentOS Stream 10 bootc, Fedora bootc, Bluefin LTS):
   ```bash
   sudo bootc switch ghcr.io/<owner>/dank-ws:latest
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
just build-qcow2      # output/qcow2/disk.qcow2 via bootc-image-builder + image.toml
just build-iso        # output/bootiso/install.iso via iso.toml
```

Before building images, edit the placeholder user/password in `image.toml`, and the
`ghcr.io/kmf/dank-ws:latest` reference in `iso.toml` (and `IMAGE_VENDOR` in the Containerfile) if you are not `kmf`.

## Status / caveats

- The image builds with podman on CentOS Stream 10 and passes `bootc container lint --fatal-warnings`;
  it has not yet been booted/tested on hardware or in a VM.
- greetd/greeter details to verify on first boot: `getent passwd greeter`, `/var/cache/dms-greeter`
  ownership, `systemctl status greetd`. If the `greetd` package from `kmf/dank-ws-copr` uses a
  different default user (its spec rewrites `greeter` to `greetd`), keep `user =` in
  `system_files/etc/greetd/config.toml` consistent with the account that exists.
- Only `linux/amd64` is built by the workflow; add an arm64 runner matrix only after checking that
  every COPR has aarch64 builds.
