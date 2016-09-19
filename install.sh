#!/bin/bash

set -e

if [ -z "$DATADIR" -o -z "$HOST" ] ; then
	echo "Not sure where FreeIPA data should be stored." >&2
	exit 1
fi

if [ -f "$HOST$DATADIR"/etc/ipa/default.conf ] ; then
	echo "FreeIPA seems already initialized in [$DATADIR]." >&2
	exit 1
fi

mkdir -p "$HOST$DATADIR"

HOSTNAME_PARAM=

i=0
while [[ $i -lt $# ]] ; do
	case "${!i}" in
		--hostname)
			i=$(( i + 1 ))
			HOSTNAME_PARAM="${!i}"
			;;
		--hostname=*)
			HOSTNAME_PARAM="${!i%%--hostname=}"
			;;
	esac
	i=$(( i + 1 ))
done

if [ -z "$HOSTNAME_PARAM" ] ; then
	NAME_PARAM=''
	if [ -n "$NAME" ] ; then
		NAME_PARAM=" --name $NAME"
	fi
	echo "Please specify the hostname for the server with --hostname parameter." >&2
	echo "Usage: atomic install$NAME_PARAM $IMAGE --hostname FQDN.of.the.IPA.server" >&2
	exit 1
fi

echo "--rm" > "$HOST$DATADIR"/docker-run-opts
echo "--hostname=$HOSTNAME_PARAM" >> "$HOST$DATADIR"/docker-run-opts
echo "$HOSTNAME_PARAM" > "$HOST$DATADIR"/hostname

chroot "$HOST" /usr/bin/docker run -ti --rm \
	-e NAME="$NAME" -e IMAGE="$IMAGE" \
	-v "$DATADIR":/data:Z -v /sys/fs/cgroup:/sys/fs/cgroup:ro -v /dev/urandom:/dev/random:ro --tmpfs /run --tmpfs /tmp -h "$HOSTNAME_PARAM" "$IMAGE" exit-on-finished "$@"
