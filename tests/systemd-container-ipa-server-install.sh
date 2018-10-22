#!/bin/bash

set -e
# set -x

C="$1"
shift

if ! docker exec $C ipa-server-install -U -r EXAMPLE.TEST -p Secret123 -a Secret123 --setup-dns --no-forwarders --no-ntp ; then
	docker exec $C journalctl -l --no-pager || :
	exit 1
fi
MACHINE_ID=$( docker exec $C cat /etc/machine-id )
docker exec $C ls -la /var/log/journal/$MACHINE_ID/system.journal /var/log/ipaserver-install.log

echo OK $0.

