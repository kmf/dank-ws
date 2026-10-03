# dank-ws-nvidia: remind the user to enroll the Secure Boot key if the NVIDIA modules
# cannot load because it is missing. Silent when Secure Boot is off or already enrolled.
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
if [ -n "${DANK_WS_MOK_HINT_SHOWN:-}" ] || ! command -v mokutil >/dev/null 2>&1; then return 0 2>/dev/null || exit 0; fi
if mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled' \
   && ! mokutil --test-key /etc/pki/akmods/certs/akmods-ublue.der 2>/dev/null | grep -q 'already enrolled'; then
    echo "dank-ws-nvidia: Secure Boot is on and the NVIDIA module signing key is not enrolled."
    echo "               Run: dank-ws-enroll-mok   (then reboot and finish in the MOK screen)"
fi
export DANK_WS_MOK_HINT_SHOWN=1
