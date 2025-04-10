#!/bin/bash

set -e
set -x

#
# Example of preparing data image for upgrade testing:
# check /etc/hosts and /etc/resolv.conf
# replica=none docker=podman VOLUME=volume-fedora-42-4.12.2 tests/run-master-and-replica.sh quay.io/freeipa/freeipa-server:volume-fedora-42-4.12.2
# podman exec -ti freeipa-master bash and check /data/var/lib/ipa/sysrestore/*-resolv.conf
# podman rm -f freeipa-master
# tests/pack-data-as-image.sh volume-fedora-42-4.12.2 data-fedora-42-4.12.2
# podman login quay.io
# TMPDIR=/tmp podman push quay.io/freeipa/freeipa-server:data-fedora-42-4.12.2
# podman login index.docker.io
# podman tag quay.io/freeipa/freeipa-server:data-fedora-42-4.12.2 docker.io/freeipa/freeipa-server:data-fedora-42-4.12.2
# TMPDIR=/tmp podman push docker.io/freeipa/freeipa-server:data-fedora-42-4.12.2
#

podman volume export $1 > $1.tar
SUM=$( sha256sum $1.tar )
SUM=${SUM%% *}
mv $1.tar $SUM.tar
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
      "created_by": "/bin/sh -c #(nop) DATA VOLUME $1"
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
podman tag $( cat $2.image ) quay.io/freeipa/freeipa-server:$2

