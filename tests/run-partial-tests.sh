#!/bin/bash

set -e
# set -x

DIR=$( dirname $0 )

DOCKERFILE="$1"
if [ -z "$DOCKERFILE" ] ; then
	echo "Usage: $0 Dockerfile-to-process" >&2
	exit 1
fi

export docker=${docker:-docker}

function run_and_wait_for () {
	(
	set +x
	local IMAGE="$1"
	local NAME="$2"
	SEC_OPTS=
	if [ "$docker" != "sudo podman" ] && [ -n "$seccomp" ] ; then
		SEC_OPTS="--security-opt=seccomp:$seccomp"
	fi
	$docker run --name $NAME -d -h ipa.example.test \
		--tmpfs /run --tmpfs /tmp -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		$SEC_OPTS --sysctl net.ipv6.conf.all.disable_ipv6=0 $IMAGE
	for j in $( seq 1 30 ) ; do
		if $docker exec $NAME systemctl is-system-running --no-pager -l 2> /dev/null | grep -q -E 'running|degraded' ; then
			return
		fi
		if ! $docker ps | grep -q "\b$NAME$" ; then
			return
		fi
		sleep 2
	done
	)
}

SUFFIX=${DOCKERFILE#Dockerfile.}

END=$( wc -l < "$DOCKERFILE" )
START=1
while [ "$START" -lt "$END" ] ; do
	SED_TO_NEXT_TEST='1,/^# test:/{s/^# \(debug\|test-add\):\s*//;p}'
	if [ "$START" = '1' ] ; then
		echo "# This line is commented out to match line count" > "$DOCKERFILE.part"
		sed -n "$SED_TO_NEXT_TEST" "$DOCKERFILE" >> "$DOCKERFILE.part"
	else
		echo "FROM local/freeipa-server-test:$SUFFIX" > "$DOCKERFILE.part"
		sed -n "1,${START}{s/^/## /;p;d};$SED_TO_NEXT_TEST" "$DOCKERFILE" >> "$DOCKERFILE.part"
	fi

	TEST_SCRIPT=$( sed -n '$s/^# test:\s*//;T;s/\( \|$\)/ 'freeipa-server-container-$SUFFIX' /;p' "$DOCKERFILE.part" )
	if [ -n "$TEST_SCRIPT" ] ; then
		$docker build -t "local/freeipa-server-test:$SUFFIX" -f "$DOCKERFILE.part" .
		echo "FROM local/freeipa-server-test:$SUFFIX" > "$DOCKERFILE.part.addons"
		sed -n 's/# test-addon:\s*//;T;p' "$DOCKERFILE.part" >> "$DOCKERFILE.part.addons"
		$docker build -t "local/freeipa-server-test-addons:$SUFFIX" -f "$DOCKERFILE.part.addons" .
		$docker rm -f freeipa-server-container-$SUFFIX > /dev/null 2>&1 || :
		# Starting systemd container
		run_and_wait_for local/freeipa-server-test-addons:$SUFFIX freeipa-server-container-$SUFFIX
		echo Executing $DIR/$TEST_SCRIPT
		$DIR/$TEST_SCRIPT
	else
		break
	fi

	START=$( wc -l < "$DOCKERFILE.part" )
	START=$(( START - 1 ))
done

echo OK $0.

