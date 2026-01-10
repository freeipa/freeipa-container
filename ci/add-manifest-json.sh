#!/bin/bash

set -e

TAG="$1"
IMAGE_FILE="$2"
if [ -z "$TAG" -o -z "$IMAGE_FILE" ] ; then
	echo "usage: $( basename $0 ) image-tag image-archive.tar-or-directory-with-extracted-content" >&2
	echo "   eg: $( basename $0 ) localhost/image-name:latest /tmp/image-name.tar" >&2
	echo "   eg: $( basename $0 ) localhost/image-name:v1.3 /tmp/image-name-v1.3/" >&2
	exit 1
fi

if [ -d "$IMAGE_FILE" -a -f "$IMAGE_FILE/manifest.json" ] \
	|| [ -f "$IMAGE_FILE" ] && tar tf $IMAGE_FILE manifest.json > /dev/null 2>&1 ; then
	echo "There already is a manifest.json there."
	exit
fi

TMPDIR=${TMPDIR:-/tmp}/freeipa-archive-$$
if [ -d "$IMAGE_FILE" ] ; then
	TMPDIR=$IMAGE_FILE
else
	rm -rf $TMPDIR
	mkdir -p $TMPDIR
fi

if [ -f "$IMAGE_FILE" ] ; then
	tar x -C $TMPDIR -f $IMAGE_FILE index.json
fi
test -f $TMPDIR/index.json
mv $TMPDIR/index.json $TMPDIR/index.json.orig
jq --arg TAG "$TAG" -f /dev/stdin <<'EOS' $TMPDIR/index.json.orig > $TMPDIR/index.json
	if .manifests | length > 1
		then error("unexpected multiple manifests found in " + input_filename)
		end
	| if .manifests[0].mediaType != "application/vnd.oci.image.manifest.v1+json"
		then error("unexpected media type declared for manifest in " + input_filename)
		end
	# podman load seems to ignore manifest.json when index.json is present
	# and it needs this annotation to tag the loaded image properly
	| .manifests[0].annotations = ( ( .manifests[0].annotations // {} ) + { "io.containerd.image.name" : $TAG } )
EOS
rm -f $TMPDIR/index.json.orig

OCI_MANIFEST=$( jq -r -f /dev/stdin <<'EOS' $TMPDIR/index.json
	.manifests[0].digest | sub("^sha256:"; "blobs/sha256/")
EOS
)
test -n "$OCI_MANIFEST"
if [ -f "$IMAGE_FILE" ] ; then
	tar x -C $TMPDIR -f $IMAGE_FILE "$OCI_MANIFEST"
fi
test -f $TMPDIR/$OCI_MANIFEST

jq --arg TAG "$TAG" -f /dev/stdin <<'EOS' $TMPDIR/$OCI_MANIFEST > $TMPDIR/manifest.json
        if .mediaType != "application/vnd.oci.image.manifest.v1+json"
                then error("unexpected media type found in oci manifest " + input_filename)
                end
        | if .config.mediaType != "application/vnd.oci.image.config.v1+json"
                then error("unexpected media type declared for config in " + input_filename)
                end
| [
{
	"Config": ( .config.digest | sub("^sha256:"; "blobs/sha256/") ),
	"RepoTags": [ $TAG ],
	"Layers": [
		( .layers[].digest | sub("^sha256:"; "blobs/sha256/") )
	]
}
]
EOS

if [ -f "$IMAGE_FILE" ] ; then
	tar r -C $TMPDIR -vf $IMAGE_FILE --owner=0 --group=0 --numeric-owner manifest.json index.json
fi

