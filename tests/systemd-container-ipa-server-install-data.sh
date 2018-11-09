#!/bin/bash

set -e
# set -x

C="$1"
D="$2"

if ! docker exec $C ipa-server-install -U -r EXAMPLE.TEST -p Secret123 -a Secret123 --setup-dns --no-forwarders --no-ntp ; then
	FAILED=$( docker exec $C systemctl list-units --state=failed --no-pager -l --no-legend | tee /dev/stderr | sed 's/ .*//' | sort )
	for s in $FAILED ; do
		docker exec $C systemctl status $s --no-pager -l || :
	done
	exit 1
fi
echo Secret123 | docker exec -i $C kinit admin
docker exec $C ipa user-add --first Bob --last Nowak bob
docker exec $C id bob

MACHINE_ID=$( docker exec $C cat /etc/machine-id )
docker exec $C ls -la /data/var/log/journal/$MACHINE_ID/system.journal /data/var/log/ipaserver-install.log
if [ -z "$TRAVIS" ] ; then
	ls -la /var/log/journal/$MACHINE_ID
	if test -f /var/log/journal/$MACHINE_ID/system.journal ; then
		exit 1
	fi
fi

docker diff $C | tee /dev/stderr | sort | diff tests/$D /dev/stdin

echo OK $0.

