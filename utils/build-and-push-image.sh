#!/bin/bash

##
# BAPI_DOCKERFILE    Indicate the Dockerfile to be used; by default it is 'Dockerfile'.
# BAPI_REMOTE_IMAGE  The reference to the remote image, indicating the image registry.
# BAPI_LOCAL_TAG     Local reference to be used for the image.
# BAPI_USERNAME      The username to login in the remote image registry.
# BAPI_PASSWORD      The password to login in the remote image registry.
##


function verbose
{
    echo "$@"; "$@"
}


function yield
{
    echo "$*" >&2
}


function error-msg
{
    yield "ERROR:$*"
}


function die
{
    local err=$?
    [ $err -eq 0 ] && err=127
    error-msg "$@"
    exit $err
}


set -o pipefail
[ "${BAPI_USERNAME}" != "" ] || die "BAPI_USERNAME variable can not be empty"
[ "${BAPI_PASSWORD}" != "" ] || die "BAPI_PASSWORD variable can not be empty"
if [ "$BAPI_REMOTE_IMAGE" == "" ] || [ "$BAPI_LOCAL_TAG" == "" ]
then
    BAPI_GIT_HASH="$( git rev-parse --short HEAD )"
fi
BAPI_DOCKERFILE="${BAPI_DOCKERFILE:-Dockerfile}"
BAPI_REMOTE_IMAGE="${BAPI_REMOTE_IMAGE:-docker.io/freeipa/freeipa-server:dev-${BAPI_GIT_HASH}}"
BAPI_LOCAL_TAG="${BAPI_LOCAL_TAG:-localhost/freeipa/freeipa-server:dev-${BAPI_GIT_HASH}}"
BAPI_TMP="$( mktemp /tmp/bapi-XXXXXX )"
buildah --storage-driver vfs bud --isolation chroot -t "${BAPI_LOCAL_TAG}" -t "${BAPI_REMOTE_IMAGE}" -f "${BAPI_DOCKERFILE}" . | tee "${BAPI_TMP}" || exit 1
BAPI_IMAGE_ID="$( tail -n 1 "${BAPI_TMP}" )"
echo "> Pushing image to '${BAPI_REMOTE_IMAGE}'"
[ $? -eq 0 ] && buildah --storage-driver vfs push --creds "${BAPI_USERNAME}:${BAPI_PASSWORD}" "${BAPI_IMAGE_ID}" "docker://${BAPI_REMOTE_IMAGE}"
rm -f "${BAPI_TMP}"
