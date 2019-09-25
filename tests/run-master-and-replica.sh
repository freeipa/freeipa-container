#!/bin/bash

set -e
set -x

umask 0007

docker=${docker:-docker}

function wait_for_ipa_container() {
	set +x
	N="$1" ; shift
	set -e
	MACHINE_ID=''
	$docker logs -f "$N" &
	EXIT_STATUS=999
	while true ; do
		sleep 10
		if [ -z "$MACHINE_ID" ] ; then
			MACHINE_ID=$( $docker exec "$N" cat /etc/machine-id || : )
		fi
		if [ "$( $docker inspect "$N" --format='{{.State.Status}}' )" == exited ] ; then
			EXIT_STATUS=$( $docker inspect "$N" --format='{{.State.ExitCode}}' )
			echo "The container has exited with .State.ExitCode [$EXIT_STATUS]."
			break
		elif [ "$1" != "exit-on-finished" ] ; then
			# With exit-on-finished, we expect the container to exit, seeing it exited above
			STATUS=$( $docker exec "$N" systemctl is-system-running 2> /dev/null || : )
			if [ "$STATUS" == 'running' ] ; then
				echo "The container systemctl is-system-running [$STATUS]."
				EXIT_STATUS=0
				break
			elif [ "$STATUS" == 'degraded' ] ; then
				echo "The container systemctl is-system-running [$STATUS]."
				EXIT_STATUS=1
				break
			fi
		fi
	done
	date
	if [ "$EXIT_STATUS" -ne 0 ] ; then
		exit "$EXIT_STATUS"
	fi
	if $docker exec "$N" grep '^2' /data/volume-version \
		&& $docker diff "$N" | tee /dev/stderr | grep -v '^C /etc$' | grep -Evf tests/docker-diff-ipa.out | grep . ; then
		exit 1
	fi
	if [ -n "$MACHINE_ID" ] ; then
		# Check that journal landed on volume and not in host's /var/log/journal
		sudo ls -la $VOLUME/var/log/journal/$MACHINE_ID
		if ls -la /var/log/journal/$MACHINE_ID ; then
			exit 1
		fi
	fi
}

function run_ipa_container() {
	set +x
	IMAGE="$1" ; shift
	N="$1" ; shift
	set -e
	date
	VOLUME=/tmp/freeipa-test-$$/data
	HOSTNAME=ipa.example.test
	if [ "$N" == "freeipa-replica" ] ; then
		HOSTNAME=replica.example.test
		VOLUME=/tmp/freeipa-test-$$/data-replica
	fi
	mkdir -p $VOLUME
	SEC_OPTS=
	if [ "$docker" != "sudo podman" ] && [ -n "$seccomp" ] ; then
		SEC_OPTS="--security-opt=seccomp:$seccomp"
	fi
	VOLUME_OPTS=
	if [ -n "$readonly" -a -n "$TRAVIS" ] ; then
		if ! [ -f $VOLUME/etc/machine-id ] ; then
			mkdir -p $VOLUME/etc
			chmod o+rx $VOLUME/etc
			uuidgen | sed 's/-//g' > $VOLUME/etc/machine-id
			chmod 444 $VOLUME/etc/machine-id
		fi
		VOLUME_OPTS="-v $VOLUME/etc/machine-id:/etc/machine-id:ro,Z"
	fi
	(
	set -x
	umask 0
	$docker run $readonly -d --name "$N" -h $HOSTNAME \
		$SEC_OPTS --sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		-v $VOLUME:/data:Z $VOLUME_OPTS $DOCKER_RUN_OPTS \
		-e PASSWORD=Secret123 "$IMAGE" "$@"
	)
	wait_for_ipa_container "$N" "$@"
}

IMAGE="$1"

if [ "$readonly" == "--read-only" ] ; then
	readonly="$readonly --dns=127.0.0.1"
fi

# Initial setup of the FreeIPA server
run_ipa_container $IMAGE freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp $ca

if [ -n "$ca" ] ; then
	$docker rm -f freeipa-master
	date
	sudo tests/generate-external-ca.sh /tmp/freeipa-test-$$/data
	# For external CA, provide the certificate for the second stage
	run_ipa_container $IMAGE freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp \
		--external-cert-file=/data/ipa.crt --external-cert-file=/data/ca.crt
fi

while [ -n "$1" ] ; do
	IMAGE="$1"
	$docker rm -f freeipa-master
	# Start the already-setup master server, or upgrade to next image
	run_ipa_container $IMAGE freeipa-master exit-on-finished
	shift
done

(
set -x
date
$docker stop freeipa-master
date
$docker start freeipa-master
)
wait_for_ipa_container freeipa-master

$docker rm -f freeipa-master
# Force "upgrade" path by simulating image change
sudo mv /tmp/freeipa-test-$$/data/build-id /tmp/freeipa-test-$$/data/build-id.initial
uuidgen | sudo tee /tmp/freeipa-test-$$/data/build-id
sudo touch -r /tmp/freeipa-test-$$/data/build-id.initial /tmp/freeipa-test-$$/data/build-id
run_ipa_container $IMAGE freeipa-master

if [ "$replica" = 'none' ] ; then
	echo OK $0.
	exit
fi

# Setup replica
MASTER_IP=$( $docker inspect --format '{{ .NetworkSettings.IPAddress }}' freeipa-master )
DOCKER_RUN_OPTS="--dns=$MASTER_IP"
if [ "$docker" != "sudo podman" ] ; then
	DOCKER_RUN_OPTS="--link freeipa-master:ipa.example.test $DOCKER_RUN_OPTS"
fi
run_ipa_container $IMAGE freeipa-replica ipa-replica-install -U --skip-conncheck --principal admin --setup-ca --no-ntp
date
if $docker diff freeipa-master | tee /dev/stderr | grep -v '^C /etc$' | grep -Evf tests/docker-diff-ipa.out | grep . ; then
	exit 1
fi
echo OK $0.
