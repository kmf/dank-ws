# dank-ws-image

A CentOS Stream 10 [bootc](https://containers.github.io/bootc/) image, modelled on
[bluefin-lts](https://github.com/ublue-os/bluefin-lts), that ships:

- **niri** (compositor) + **DankMaterialShell** (`dms`, `quickshell-git`, `matugen`, `cliphist`, `danksearch`, `dgop`, `dankcalendar-git`)
- **ghostty** and **kitty** terminals
- **dms-greeter** on **greetd** as the login screen (replaces gdm if present)
- `cava`, `kf6-kimageformats`

Packages come from EPEL/CRB plus the COPRs `avengemedia/danklinux`, `avengemedia/dms-git`,
`yalter/niri` and [`kmf/dank-ws-copr`](https://github.com/kmf/dank-ws-copr).
The COPR repos are disabled again at the end of the build.

**Hyprland is intentionally not included**: `kmf/dank-ws-copr` ships a rebuilt `lua` 5.5 for it,
which conflicts with el10's stock `lua-libs` 5.4 (needed by `wireplumber-libs`, `ibus-libpinyin`).

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | The image (`ARG BASE_TAG` selects the `centos-bootc` tag, default `c10s`) |
| `system_files/` | Copied into `/`: `/etc/greetd/config.toml`, greeter sysusers + tmpfiles |
| `.github/workflows/build.yml` | Build, push to GHCR, sign with cosign (weekly + on push to `main`) |
| `Justfile` | `build`, `build-qcow2`, `build-iso`, `check`, `clean` |
| `image.toml` / `iso.toml` | bootc-image-builder configs (VM disk / installer ISO) |

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

- Scaffolded but **not yet built**: no container runtime was available where this was generated.
  Expect to iterate on the first `podman build`.
- `bootc container lint --fatal-warnings` may flag things only visible in a real build
  (e.g. users created by RPM scriptlets without sysusers entries).
- greetd/greeter details to verify on first boot: `getent passwd greeter`, `/var/cache/dms-greeter`
  ownership, `systemctl status greetd`. If the `greetd` package from `kmf/dank-ws-copr` uses a
  different default user (its spec rewrites `greeter` to `greetd`), keep `user =` in
  `system_files/etc/greetd/config.toml` consistent with the account that exists.
- Only `linux/amd64` is built by the workflow; add an arm64 runner matrix only after checking that
  every COPR has aarch64 builds.
