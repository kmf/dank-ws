export image_name := env("IMAGE_NAME", "dank-ws")
export base_tag := env("BASE_TAG", "c10s")
export default_tag := env("DEFAULT_TAG", "latest")
export dms_channel := env("DMS_CHANNEL", "rolling")
export nvidia_image_name := env("NVIDIA_IMAGE_NAME", "dank-ws-nvidia")
export akmods_nvidia_image := env("AKMODS_NVIDIA_IMAGE", "ghcr.io/ublue-os/akmods-nvidia-open:centos-10")
export iso_owner := env("ISO_OWNER", "kmf")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")

alias build-vm := build-qcow2

[private]
default:
    @just --list

# Check Justfile syntax
[group('Just')]
check:
    just --unstable --fmt --check -f Justfile

# Build the container image into root's podman storage (needed by bootc-image-builder)
# Parameters:
#   target_image: image name (default: localhost/dank-ws)
# tag: image tag (default: latest)
[group('Build')]
build target_image=("localhost/" + image_name) tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo podman build \
        --pull=newer \
        --build-arg BASE_TAG="{{ base_tag }}" \
        --build-arg DMS_CHANNEL="{{ dms_channel }}" \
        --build-arg IMAGE_NAME="{{ image_name }}" \
        --tag "{{ target_image }}:{{ tag }}" \
        -f Containerfile .

# Build the NVIDIA variant (proprietary driver, kernel from ublue-os akmods) into root's podman storage
# Parameters:
#   target_image: image name (default: localhost/dank-ws-nvidia)
#   tag: image tag (default: latest)
[group('Build')]
build-nvidia target_image=("localhost/" + nvidia_image_name) tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo podman build \
        --pull=newer \
        --build-arg BASE_TAG="{{ base_tag }}" \
        --build-arg DMS_CHANNEL="{{ dms_channel }}" \
        --build-arg IMAGE_NAME="{{ nvidia_image_name }}" \
        --build-arg ENABLE_NVIDIA=1 \
        --build-arg AKMODS_NVIDIA_IMAGE="{{ akmods_nvidia_image }}" \
        --tag "{{ target_image }}:{{ tag }}" \
        -f Containerfile .

# Internal: run bootc-image-builder
# Parameters: target_image tag type config
[private]
_build-bib target_image tag type config:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    sudo rm -rf "output/{{ type }}"
    sudo podman run \
        --rm -it --privileged --pull=newer --net=host \
        --security-opt label=type:unconfined_t \
        -v "$(pwd)/{{ config }}":/config.toml:ro \
        -v "$(pwd)/output":/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "{{ bib_image }}" \
        --type "{{ type }}" \
        --use-librepo=True \
        "{{ target_image }}:{{ tag }}"
    sudo chown -R "$USER:$USER" output

# Build a QCOW2 VM image (output/qcow2/disk.qcow2) using image.toml
[group('Build Virtual Machine Image')]
build-qcow2 target_image=("localhost/" + image_name) tag=default_tag: (build target_image tag) (_build-bib target_image tag "qcow2" "image.toml")

# Build a QCOW2 VM image of the NVIDIA variant (output/qcow2/disk.qcow2)
[group('Build Virtual Machine Image')]
build-qcow2-nvidia target_image=("localhost/" + nvidia_image_name) tag=default_tag: (build-nvidia target_image tag) (_build-bib target_image tag "qcow2" "image.toml")

# Internal: build the INTERACTIVE installer ISO for one variant
# Parameters: name (dank-ws|dank-ws-nvidia) target_image tag
# Output: output/<name>/bootiso/install.iso (embeds target_image, so the install works offline)
[private]
_build-iso name target_image tag:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "output/{{ name }}"
    sudo rm -rf "output/{{ name }}/bootiso"
    # iso.toml is a template: @IMAGE@ is the GHCR image the installed system is switched to
    sed "s|@IMAGE@|ghcr.io/{{ iso_owner }}/{{ name }}:latest|" iso.toml > "output/{{ name }}/iso.toml"
    sudo podman run \
        --rm --privileged --pull=newer --net=host \
        --security-opt label=type:unconfined_t \
        -v "$(pwd)/output/{{ name }}/iso.toml":/config.toml:ro \
        -v "$(pwd)/output/{{ name }}":/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "{{ bib_image }}" \
        --type anaconda-iso \
        --use-librepo=True \
        "{{ target_image }}:{{ tag }}"
    sudo chown -R "$USER:$USER" output
    ls -lh "output/{{ name }}/bootiso/install.iso"

# Build the interactive installer ISO for dank-ws (output/dank-ws/bootiso/install.iso)
[group('Build Virtual Machine Image')]
build-iso target_image=("localhost/" + image_name) tag=default_tag: (build target_image tag) (_build-iso image_name target_image tag)

# Build the interactive installer ISO for dank-ws-nvidia (output/dank-ws-nvidia/bootiso/install.iso)
[group('Build Virtual Machine Image')]
build-iso-nvidia target_image=("localhost/" + nvidia_image_name) tag=default_tag: (build-nvidia target_image tag) (_build-iso nvidia_image_name target_image tag)

# Remove build output
[group('Build')]
clean:
    sudo rm -rf output
