#!/bin/bash

set -e
# set -x

C="$1"
shift

docker=${docker:-docker}

$docker exec $C systemctl status --no-pager -l
if [ "$#" -eq 0 ] ; then
	$docker exec $C systemctl is-system-running --no-pager -l | grep running
	echo OK $0.
	exit
fi

$docker exec $C systemctl is-system-running --no-pager -l | grep -E 'degraded|starting'
$docker exec $C journalctl --no-pager -l

FAILED=$( $docker exec $C systemctl list-units --state=failed --no-pager -l --no-legend --plain | tee /dev/stderr | sed 's/ .*//' | sort )
for s in $FAILED ; do
	$docker exec $C systemctl status $s --no-pager -l || :
done

diff <( for i in "$@" ; do echo $i ; done ) <( for s in $FAILED ; do echo $s ; done )

echo OK $0.

