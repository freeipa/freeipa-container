#!/bin/bash

set -e
# set -x

C="$1"
shift

docker=${docker:-docker}

EXIT=false
if ! $docker exec $C ipa-server-install -U -r EXAMPLE.TEST -p Secret123 -a Secret123 --setup-dns --no-forwarders --no-ntp ; then
	EXIT=true
fi
FAILED=$( $docker exec $C systemctl list-units --state=failed --no-pager -l --no-legend | tee /dev/stderr | sed 's/ .*//' | sort )
for s in $FAILED ; do
	$docker exec $C systemctl status $s --no-pager -l || :
done
if [ -n "$FAILED" ] ; then
	EXIT=true
fi
if $EXIT ; then
	exit 1
fi
$docker exec $C ls -la /var/log/ipaserver-install.log
MACHINE_ID=$( $docker exec $C cat /etc/machine-id )
! $docker exec $C ls -la /var/log/journal/$MACHINE_ID
$docker exec $C ls -la /run/log/journal/$MACHINE_ID/system.journal

echo OK $0.

