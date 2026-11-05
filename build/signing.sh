#!/usr/bin/env bash
# Enforce cosign signatures for this project's images on installed systems
# (same layout as Bluefin's ublue-os-signing, with the key under /usr so image
# updates always replace it — /etc is subject to ostree 3-way merge drift):
#   /usr/lib/pki/containers/dux-ws.pub        public key (copied from cosign.pub by the Containerfile)
#   /etc/containers/registries.d/dux-ws.yaml  read cosign signatures stored as registry attachments
#   /etc/containers/policy.json               distro default policy + sigstoreSigned entries for our images
# Existing installs whose /etc/containers/policy.json still names the old
# /etc/pki/containers/dux-ws.pub path are repaired on boot by
# dux-ws-signing-migrate.service (syncs the /etc key from /usr and rewrites keyPath).
# Usage: signing.sh <registry-namespace, e.g. ghcr.io/kmf> <image-name>...
set -euo pipefail

NAMESPACE="$1"
shift
PUBKEY=/usr/lib/pki/containers/dux-ws.pub

test -s "${PUBKEY}"

install -d /etc/containers/registries.d
cat > /etc/containers/registries.d/dux-ws.yaml <<EOT
docker:
  ${NAMESPACE}:
    use-sigstore-attachments: true
EOT

# Start from the distro default policy (keeps its Red Hat registry entries) and
#  - add one sigstoreSigned requirement per image. The scope is the repository, so it covers
#    every tag and digest of that image but not sibling repositories;
#  - switch the global default to "reject" and explicitly accept every other transport/registry
#    instead (the same effective behaviour as the distro default). bootc refuses
#    `--enforce-container-sigpolicy` when the policy default is insecureAcceptAnything,
#    so this is what makes enforcement work (same shape as Bluefin's ublue-os-signing policy).
src=/usr/share/containers/policy.json
[ -f /etc/containers/policy.json ] && src=/etc/containers/policy.json
entries='{}'
for img in "$@"; do
    entries=$(jq --arg scope "${NAMESPACE}/${img}" --arg key "${PUBKEY}" \
        '. + {($scope): [{type: "sigstoreSigned", keyPath: $key, signedIdentity: {type: "matchRepository"}}]}' <<<"${entries}")
done
jq --argjson e "${entries}" '
    def accept: [{type: "insecureAcceptAnything"}];
    .default = [{type: "reject"}]
    | .transports.docker += $e
    | .transports.docker[""] = accept
    | .transports["docker-daemon"][""] = accept
    | .transports["containers-storage"][""] = accept
    | .transports["oci"][""] = accept
    | .transports["oci-archive"][""] = accept
    | .transports["docker-archive"][""] = accept
    | .transports["dir"][""] = accept' "${src}" > /etc/containers/policy.json.new
mv /etc/containers/policy.json.new /etc/containers/policy.json
jq -e . /etc/containers/policy.json > /dev/null
# Fail the build if any of our image scopes still point at a non-/usr key.
for img in "$@"; do
    jq -e --arg scope "${NAMESPACE}/${img}" --arg key "${PUBKEY}" '
        .transports.docker[$scope][0].type == "sigstoreSigned"
        and .transports.docker[$scope][0].keyPath == $key
    ' /etc/containers/policy.json > /dev/null
done
