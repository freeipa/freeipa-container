#!/bin/bash

# Annotate recently built image with labels about the content of the image

set -e

docker=${docker:-docker}

DOCKERFILE="$1"
TAG="$2"
GITTREE="$3"
REPO_URL="$4"
JOB_PATH="$5"

COMMIT=$( git rev-parse HEAD )
test -n "$COMMIT"
FROM=$( awk '/^FROM / { print $2 ; exit }' "$DOCKERFILE" )
test -n "$FROM"
CREATED="$( date --utc --rfc-3339=seconds )"

# Sadly we cannot --filter specific image because in that case docker
# does not show the digest
BASE_DIGEST=$( $docker images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | awk -v image="$FROM" '$1 == image { print $2 }' )
if [ -z "$BASE_DIGEST" ] ; then
	# Since docker images strips the docker.io/ prefix, try again without it
	BASE_DIGEST=$( $docker images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | awk -v image="${FROM#docker.io/}" '$1 == image { print $2 }' )
fi
if [ -z "$BASE_DIGEST" ] ; then
	# When FROM does not specify a tag, try again with :latest
	BASE_DIGEST=$( $docker images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | awk -v image="$FROM:latest" '$1 == image { print $2 }' )
fi
if [ -z "$BASE_DIGEST" ] ; then
	# When FROM does not specify a tag, try again with :latest
	BASE_DIGEST=$( $docker images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | awk -v image="${FROM#docker.io/}:latest" '$1 == image { print $2 }' )
fi
test -n "$BASE_DIGEST"

IPA_VERSION=$( $docker run --rm --entrypoint rpm "$TAG" -qf --qf '%{version}\n' /usr/sbin/ipa-server-install )
test -n "$IPA_VERSION"
RPM_QA_SHA=$( $docker run --rm --entrypoint rpm "$TAG" -qa | LC_COLLATE=C sort | sha256sum | sed 's/ .*//' )
test -n "$RPM_QA_SHA"
if test -z "$GITTREE" ; then
	GITTREE=$( git write-tree )
fi
test -n "$GITTREE"

declare -a OPTS
TITLE="$( $docker inspect "$TAG" --format '{{ index .Config.Labels "org.opencontainers.image.title" }}' )"
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels.name' > /dev/null ; then
	OPTS+=(--label "name=$TITLE")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."io.k8s.display-name"' > /dev/null ; then
	OPTS+=(--label "io.k8s.display-name=$TITLE")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."org.label-schema.name"' > /dev/null ; then
	OPTS+=(--label "org.label-schema.name=$TITLE")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."summary"' > /dev/null ; then
	OPTS+=(--label "summary=$TITLE")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels.version' > /dev/null ; then
	OPTS+=(--label version=$IPA_VERSION)
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels.release' > /dev/null ; then
	OPTS+=(--label release=rpms-$RPM_QA_SHA)
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."vcs-ref"' > /dev/null ; then
	OPTS+=(--label vcs-ref=$COMMIT --label vcs-type=git)
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."build-date"' > /dev/null ; then
	OPTS+=(--label build-date="$CREATED")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."org.label-schema.build-date"' > /dev/null ; then
	OPTS+=(--label org.label-schema.build-date="$CREATED")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."com.redhat.component"' > /dev/null ; then
	OPTS+=(--label com.redhat.component=freeipa-server-container)
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."com.redhat.build-host"' > /dev/null ; then
	OPTS+=(--label com.redhat.build-host=$( hostname -f ))
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."io.openshift.tags"' > /dev/null ; then
	OPTS+=(--label "io.openshift.tags=freeipa freeipa-server identity-management $( $docker inspect "$TAG" --format '{{ index .Config.Labels "io.openshift.tags" }}' | sed 's/base //' )")
fi
DESCRIPTION="$( $docker inspect "$TAG" | jq -r '.[0].Config.Labels."org.opencontainers.image.description"' )"
if [ "$DESCRIPTION" == null ] ; then
	read -d '' DESCRIPTION <<-EOS || :
		Integrated identity management solution
		for centrally managed identities, authentication, and authorization,
		with support for cross realm trusts with Active Directory
		and with DNS server supporting automatic DNSSEC signing.
	EOS
	DESCRIPTION="$( echo $DESCRIPTION )"
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels.description' > /dev/null ; then
	OPTS+=(--label description="$DESCRIPTION")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels."io.k8s.description"' > /dev/null ; then
	OPTS+=(--label io.k8s.description="$DESCRIPTION")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels.maintainer' > /dev/null ; then
	OPTS+=(--label maintainer="$( $docker inspect "$TAG" --format '{{ index .Config.Labels "org.opencontainers.image.authors" }}' )")
fi
if $docker inspect "$TAG" | jq -e '.[0].Config.Labels.usage' > /dev/null ; then
	OPTS+=(--label usage="https://github.com/freeipa/freeipa-container#running-freeipa-server-container")
fi
if test -n "$REPO_URL" ; then
	OPTS+=(--label org.opencontainers.image.source="$REPO_URL/blob/$COMMIT/$DOCKERFILE")
fi
if test -n "$JOB_PATH" ; then
	OPTS+=(--label org.opencontainers.image.url="$REPO_URL/$JOB_PATH")
fi


# We rerun the build and assume that it will use cached layers all the way,
# so this build invocation will only add the labels
set -x
$docker build -f "$DOCKERFILE" -t "$TAG" \
	--label org.opencontainers.image.created="$CREATED" \
	--label org.opencontainers.image.revision=$COMMIT \
	--label org.opencontainers.image.version="$IPA_VERSION-rpms-$RPM_QA_SHA-gittree-$GITTREE" \
	--label org.opencontainers.image.base.name=$FROM \
	--label org.opencontainers.image.base.digest=$BASE_DIGEST \
	"${OPTS[@]}" .
