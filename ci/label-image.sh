#!/bin/bash

# Annotate recently built image with labels about the content of the image

set -e

docker=${docker:-docker}

DOCKERFILE="$1"
TAG="$2"

COMMIT=$( git rev-parse HEAD )
test -n "$COMMIT"
FROM=$( awk '/^FROM / { print $2 ; exit }' "$DOCKERFILE" )
test -n "$FROM"

# Sadly we cannot --filter specific image because in that case docker
# does not show the digest
BASE_DIGEST=$( $docker images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | awk -v image="$FROM" '$1 == image { print $2 }' )
test -n "$BASE_DIGEST"

IPA_VERSION=$( $docker run --rm --entrypoint rpm "$TAG" -qf --qf '%{version}\n' /usr/sbin/ipa-server-install )
test -n "$IPA_VERSION"
RPM_QA_SHA=$( $docker run --rm --entrypoint rpm "$TAG" -qa | LC_COLLATE=C sort | sha256sum | sed 's/ .*//' )
test -n "$RPM_QA_SHA"


# We rerun the build and assume that it will use cached layers all the way,
# so this build invocation will only add the labels
set -x
$docker build -f "$DOCKERFILE" -t "$TAG" \
	--label org.opencontainers.image.created="$( date --utc --rfc-3339=seconds )" \
	--label org.opencontainers.image.revision=$COMMIT \
	--label org.opencontainers.image.version="$IPA_VERSION-rpms-$RPM_QA_SHA" \
	--label org.opencontainers.image.base.name=$FROM \
	--label org.opencontainers.image.base.digest=$BASE_DIGEST .
