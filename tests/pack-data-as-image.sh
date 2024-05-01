#!/bin/bash

set -e
set -x

#
# Example of preparing data image for upgrade testing:
# check /etc/hosts and /etc/resolv.conf
# mkdir -p freeipa-server/data
# replica=none docker=podman VOLUME=$(pwd)/freeipa-server/data tests/run-master-and-replica.sh quay.io/freeipa/freeipa-server:fedora-39
# podman rm -f freeipa-master
# check freeipa-server/data/var/lib/ipa/sysrestore/*-resolv.conf
# tests/pack-data-as-image.sh freeipa-server data-fedora-39
# podman login quay.io
# podman tag freeipa/freeipa-server:data-fedora-39 quay.io/freeipa/freeipa-server:data-fedora-39
# TMPDIR=/tmp podman push quay.io/freeipa/freeipa-server:data-fedora-39
# podman login index.docker.io
# podman tag freeipa/freeipa-server:data-fedora-39 docker.io/freeipa/freeipa-server:data-fedora-39
# TMPDIR=/tmp podman push docker.io/freeipa/freeipa-server:data-fedora-39
#

cd "$1"
podman run --rm -v $(pwd)/data:/data:Z registry.fedoraproject.org/fedora:39 tar cf - data > data.tar
SUM=$( sha256sum data.tar )
SUM=${SUM%% *}
mv data.tar $SUM.tar
DATE=$( TZ=Z date --iso-8601=ns | sed 's/,/./; s/+00:00/Z/' )
cat <<EOF > config.json
{
  "created": "$DATE",
  "architecture": "amd64",
  "os": "linux",
  "rootfs": {
    "type": "layers",
    "diff_ids": [ "sha256:$SUM" ]
  },
  "config": {},
  "history": [
    {
      "created": "$DATE",
      "created_by": "/bin/sh -c #(nop) DATA VOLUME"
    }
  ]
}
EOF
CSUM=$( sha256sum config.json )
CSUM=${CSUM%% *}
mv config.json $CSUM.json
cat <<EOF > manifest.json
[
  {
    "Config": "$CSUM.json",
    "Layers": [ "$SUM.tar" ]
  }
]
EOF
tar -cz --owner=root:0 --group=root:0 -f "$2.tar.gz" $SUM.tar $CSUM.json manifest.json
rm -f $SUM.tar $CSUM.json manifest.json
echo "$CSUM" > "$2.image"

TMPDIR=/tmp podman load -i "$2.tar.gz"
podman tag $( cat $2.image ) freeipa/freeipa-server:$2

