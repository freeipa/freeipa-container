#!/bin/bash

if command -v podman 2>/dev/null 1>/dev/null
then
    oci="podman"
elif command -v docker 2>/dev/null 1>/dev/null
then
    oci="docker"
else
    echo "No docker nor podman was found" >&2
    exit 2
fi

$oci run --security-opt seccomp=unconfined \
         --rm -it \
         -e BAPI_USERNAME="${BAPI_USERNAME}" \
         -e BAPI_PASSWORD="${BAPI_PASSWORD}" \
         -e BAPI_REMOTE_IMAGE="${BAPI_REMOTE_IMAGE}" \
         -e BAPI_DOCKERFILE="${BAPI_DOCKERFILE}" \
         -v "$PWD:/data:z" \
         -w "/data" \
         quay.io/buildah/stable \
         ./devel/build-and-push-image.sh
