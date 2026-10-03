# starship prompt for interactive bash/zsh. Sourced by /etc/profile (login shells)
# and /etc/bashrc (non-login interactive shells), so it must be idempotent.
# Opt out per user with:  touch ~/.config/no-starship
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
# (plain, unexported variable: child shells re-init, since PS1 is not inherited)
[ -z "${__dankws_starship:-}" ] || return 0 2>/dev/null || exit 0
[ "${TERM:-dumb}" != "dumb" ] || return 0 2>/dev/null || exit 0
# plain Linux VT cannot render the glyphs; keep the stock prompt there
[ "${TERM:-}" != "linux" ] || return 0 2>/dev/null || exit 0
[ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/no-starship" ] || return 0 2>/dev/null || exit 0
command -v starship >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

# user config wins; otherwise fall back to the system default
if [ -z "${STARSHIP_CONFIG:-}" ] && [ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml" ]; then
    export STARSHIP_CONFIG=/etc/starship.toml
fi

__dankws_starship=1
if [ -n "${BASH_VERSION:-}" ]; then
    eval "$(starship init bash)"
elif [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(starship init zsh)"
fi
