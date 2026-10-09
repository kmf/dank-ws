#!/usr/bin/env bash
# Extra fonts, both image variants. EPEL RPMs where they exist (fira-code-fonts; jetbrains-mono-fonts-all
# is already installed in the main package step), otherwise pinned upstream releases verified by
# SHA-256, unpacked to /usr/share/fonts/<name>. Not in CentOS Stream 10 / EPEL 10: Fira Mono, Inconsolata,
# Geist, Nerd Fonts. Bump a version by updating its URL and checksum together.
set -xeuo pipefail

COMPONENT=fonts-extra
NF=https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1
GEIST=https://github.com/vercel/geist-font/releases/download/v1.7.2
INCONSOLATA=https://github.com/googlefonts/Inconsolata/releases/download/v3.000
FIRA=https://raw.githubusercontent.com/mozilla/Fira/4.202

rpm -q attr >/dev/null || dnf -y install attr
dnf -y --enablerepo=epel install fira-code-fonts fontconfig unzip xz

W=$(mktemp -d)
fetch() { # url sha256 -> $W/<basename>
    curl -fsSL --retry 5 -o "${W}/$(basename "$1")" "$1"
    echo "$2  ${W}/$(basename "$1")" | sha256sum -c -
}
fetch "${NF}/CodeNewRoman.tar.xz" eb902759ff5bc6c4011821c566f4001139c7c571abeb8990f3a3cdfdf661da4e
fetch "${NF}/CascadiaCode.tar.xz" ae598e9401e2846aa3ee364513715de0490b844a4b54f0768991f45f23aa8369
fetch "${NF}/CascadiaMono.tar.xz" e4fe0248bbe2558e907d26b55ed287403972f946239a4ea3f7a8afd3365ad6ba
fetch "${GEIST}/geist-font-v1.7.2.zip" 7fc800d2ac6b92844895196e5041aca55d814c15db70c44f79b3b83ab82b04e2
fetch "${INCONSOLATA}/fonts_ttf.zip" 626e8ee07501dbb544b50aa59ac2e4b9ec86b810670158a59c7a3cbaf475548a
fetch "${INCONSOLATA}/OFL.txt" 5d362a6f8690517fd9a5573128a081d8bbbb2f92714cf00556e08fbbe9600426
fetch "${FIRA}/ttf/FiraMono-Regular.ttf" 8c86f2963208a353c3435e28ecb38a99ab68f14d7433ba00c1822cef9a9c1b44
fetch "${FIRA}/ttf/FiraMono-Medium.ttf" 5f9173ce3d05fadef74c7eed06570d54e4f75bd0cd9860726fb2987a7f848292
fetch "${FIRA}/ttf/FiraMono-Bold.ttf" 2a28efd740e8da1da75d40ac79f0db4f60a0f1aead0b15ca16b4694a11b45fc6
fetch "${FIRA}/LICENSE" 3d70884eedc6b82c9563e1848bc2a8189aacf1743e39d8fc4afb860c6da031a5

D=/usr/share/fonts
# Nerd Fonts (each archive: <Family>NerdFont{,Mono,Propo}-*.{ttf,otf} + license)
for pair in CodeNewRoman:codenewroman-nerd-fonts CascadiaCode:caskaydiacove-nerd-fonts CascadiaMono:caskaydiamono-nerd-fonts; do
    src="${pair%%:*}"; dst="${D}/${pair##*:}"
    install -d -m 0755 "${dst}"
    tar -xJf "${W}/${src}.tar.xz" -C "${dst}" --no-same-owner
    rm -f "${dst}/README.md"
done
# Geist + Geist Mono (static TTFs)
mkdir -p "${W}/geist" && unzip -q "${W}/geist-font-v1.7.2.zip" -d "${W}/geist"
install -D -m 0644 -t "${D}/geist-fonts" "${W}"/geist/geist-font/Geist/ttf/*.ttf "${W}/geist/geist-font/OFL.txt"
install -D -m 0644 -t "${D}/geist-mono-fonts" "${W}"/geist/geist-font/GeistMono/ttf/*.ttf "${W}/geist/geist-font/OFL.txt"
# Inconsolata (normal width only; the release also has 8 other widths)
mkdir -p "${W}/inconsolata" && unzip -q "${W}/fonts_ttf.zip" -d "${W}/inconsolata"
install -d -m 0755 "${D}/inconsolata-fonts"
for w in ExtraLight Light Regular Medium SemiBold Bold ExtraBold Black; do
    install -m 0644 "${W}/inconsolata/fonts/ttf/Inconsolata-${w}.ttf" "${D}/inconsolata-fonts/"
done
install -m 0644 "${W}/OFL.txt" "${D}/inconsolata-fonts/OFL.txt"
# Fira Mono
install -D -m 0644 -t "${D}/fira-mono-fonts" "${W}"/FiraMono-*.ttf "${W}/LICENSE"
rm -rf "${W}"

for d in codenewroman-nerd-fonts caskaydiacove-nerd-fonts caskaydiamono-nerd-fonts geist-fonts geist-mono-fonts inconsolata-fonts fira-mono-fonts; do
    find "${D}/${d}" -type d -exec chmod 0755 {} + && find "${D}/${d}" -type f -exec chmod 0644 {} +
    find "${D}/${d}" -type f -exec setfattr -n user.component -v "${COMPONENT}" {} +
done
fc-cache -sf

# Checks: every family must be known to fontconfig.
for fam in "CodeNewRoman Nerd Font" "CaskaydiaCove Nerd Font" "CaskaydiaMono Nerd Font" \
           "Inconsolata" "Fira Code" "Fira Mono" "Geist" "Geist Mono" "JetBrains Mono"; do
    fc-list -q ":family=${fam}" || { echo "font family missing: ${fam}" >&2; fc-list : family | sort -u >&2; exit 1; }
    echo "font ok: ${fam} ($(fc-list ":family=${fam}" file | wc -l) files)"
done
