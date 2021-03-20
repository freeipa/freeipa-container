#!/bin/bash

set -e
set -x

#
# Example of preparing data image for upgrade testing:
# mkdir -p freeipa-server/data
# replica=none VOLUME=$(pwd)/freeipa-server/data tests/run-master-and-replica.sh freeipa/freeipa-server:fedora-33
# docker rm -f freeipa-master
# sudo tests/pack-data-as-image.sh freeipa-server data-fedora-33
# docker login ...
# docker push freeipa/freeipa-server:data-fedora-33
#

cd "$1"
tar cf data.tar data
SUM=$( sha256sum data.tar )
SUM=${SUM%% *}
mv data.tar $SUM.tar
cat <<EOF > config.json
{
  "created": "$( TZ=Z date --iso-8601=ns | sed 's/,/./; s/+00:00/Z/' )",
  "architecture": "amd64",
  "os": "linux",
  "rootfs": {
    "type": "layers",
    "diff_ids": [ "sha256:$SUM" ]
  }
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

