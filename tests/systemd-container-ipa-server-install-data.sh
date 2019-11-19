#!/bin/bash

set -e
# set -x

C="$1"
D="$2"

docker=${docker:-docker}

EXIT=false
if ! $docker exec $C ipa-server-install -U -r EXAMPLE.TEST -p Secret123 -a Secret123 --setup-dns --no-forwarders --no-ntp ; then
	EXIT=true
fi
if ! "$EXIT" && ! $docker exec $C ipa-adtrust-install -a Secret123 --netbios-name=EXAMPLE -U ; then
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
$docker exec $C bash -c 'echo Secret123 | kinit admin'
$docker exec $C ipa user-add --first Bob --last Nowak bob
$docker exec $C id bob

MACHINE_ID=$( $docker exec $C cat /etc/machine-id )
$docker exec $C ls -la /data/var/log/journal/$MACHINE_ID/system.journal /data/var/log/ipaserver-install.log
if ls -la /var/log/journal/$MACHINE_ID ; then
	exit 1
fi

$docker diff $C | tee /dev/stderr | grep -v '^C /etc$' | sort | diff tests/$D /dev/stdin

echo OK $0.

