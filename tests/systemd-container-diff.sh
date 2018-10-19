#!/bin/bash

set -e
# set -x

C="$1"
L="$2"
E="$3"
D="$4"

docker exec $C systemctl status --no-pager -l
FAILED=$( docker exec $C systemctl list-units --state=failed --no-pager -l --no-legend | tee /dev/stderr | sed 's/ .*//' | sort )
for s in $FAILED ; do
	docker exec $C systemctl status $s --no-pager -l || :
done
docker exec $C systemctl is-system-running --no-pager -l
docker exec $C systemctl list-dependencies -a --no-pager -l | grep -v '\.slice' | tee /dev/stderr | diff tests/$L /dev/stdin
MACHINE_ID=$( docker exec $C cat /etc/machine-id )
docker exec $C ls -la /var/log/journal/$MACHINE_ID/system.journal
if [ -z "$TRAVIS" ] ; then
        ls -la /var/log/journal/$MACHINE_ID/system.journal
fi

docker diff $C | tee /dev/stderr | grep -Evf tests/$E | sort | diff tests/$D /dev/stdin

echo OK $0.

