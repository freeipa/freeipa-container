#!/bin/bash

set -e
set -x

#
# Example of preparing data image for upgrade testing:
# mkdir -p freeipa-server/data
# replica=none VOLUME=$(pwd)/freeipa-server/data tests/run-master-and-replica.sh freeipa/freeipa-server:fedora-34
# docker rm -f freeipa-master
# sudo tests/pack-data-as-image.sh freeipa-server data-fedora-34
# docker login index.docker.io
# docker push freeipa/freeipa-server:data-fedora-34
# docker tag freeipa/freeipa-server:data-fedora-34 quay.io/freeipa/freeipa-server:data-fedora-34
# docker login quay.io
# docker push quay.io/freeipa/freeipa-server:data-fedora-34
#

cd "$1"
tar cf data.tar data
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
tar czf "$2.tar.gz" $SUM.tar $CSUM.json manifest.json
rm -f $SUM.tar $CSUM.json manifest.json
echo "$CSUM" > "$2.image"

docker load -i "$2.tar.gz"
docker tag $( cat $2.image ) freeipa/freeipa-server:$2

