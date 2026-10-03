export image_name := env("IMAGE_NAME", "dank-ws")
export base_tag := env("BASE_TAG", "c10s")
export default_tag := env("DEFAULT_TAG", "latest")
export nvidia_image_name := env("NVIDIA_IMAGE_NAME", "dank-ws-nvidia")
export akmods_nvidia_image := env("AKMODS_NVIDIA_IMAGE", "ghcr.io/ublue-os/akmods-nvidia-open:centos-10")
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
    if [[ "{{ type }}" == "anaconda-iso" ]]; then
        sudo rm -rf output/bootiso
    else
        sudo rm -rf "output/{{ type }}"
    fi
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

# Build an installer ISO (output/bootiso/install.iso) using iso.toml
[group('Build Virtual Machine Image')]
build-iso target_image=("localhost/" + image_name) tag=default_tag: (build target_image tag) (_build-bib target_image tag "anaconda-iso" "iso.toml")

# Remove build output
[group('Build')]
clean:
    sudo rm -rf output
