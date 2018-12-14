#!/bin/bash

set -e
set -x

umask 0007

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
	(
	set -x
	docker run -d --name "$N" -h $HOSTNAME \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		-v $VOLUME:/data:Z $DOCKER_RUN_OPTS \
		-e PASSWORD=Secret123 "$IMAGE" "$@"
	)
	MACHINE_ID=''
	docker logs -f "$N" &
	while true ; do
		sleep 10
		if [ -z "$MACHINE_ID" ] ; then
			MACHINE_ID=$( docker exec "$N" cat /etc/machine-id || : )
		fi
		if [ "$1" == exit-on-finished ] ; then
			if [ "$( docker inspect "$N" --format='{{.State.Status}}' )" == exited ] ; then
				echo "The container has exited, presumably because of exit-on-finished."
				break
			fi
		elif ! docker exec "$N" systemctl is-system-running 2> /dev/null | grep -Eq 'starting|initializing' ; then
			break
		fi
	done
	date
	EXIT_STATUS=$( docker inspect "$N" --format='{{.State.ExitCode}}' )
	if [ "$EXIT_STATUS" -ne 0 ] ; then
		exit "$EXIT_STATUS"
	fi
	if docker exec "$N" grep '^2' /data/volume-version \
		&& docker diff "$N" | tee /dev/stderr | grep -Evf tests/docker-diff-ipa.out | grep . ; then
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

IMAGE="$1"

# Initial setup of the FreeIPA server
run_ipa_container $IMAGE freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp $ca

if [ -n "$ca" ] ; then
	docker rm -f freeipa-master
	date
	sudo tests/generate-external-ca.sh /tmp/freeipa-test-$$/data
	# For external CA, provide the certificate for the second stage
	run_ipa_container $IMAGE freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp \
		--external-cert-file=/data/ipa.crt --external-cert-file=/data/ca.crt
fi

while [ -n "$1" ] ; do
	IMAGE="$1"
	docker rm -f freeipa-master
	# Start the already-setup master server, or upgrade to next image
	run_ipa_container $IMAGE freeipa-master exit-on-finished
	shift
done

docker rm -f freeipa-master
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
MASTER_IP=$( docker inspect --format '{{ .NetworkSettings.IPAddress }}' freeipa-master )
DOCKER_RUN_OPTS="--link freeipa-master:ipa.example.test --dns=$MASTER_IP"
run_ipa_container $IMAGE freeipa-replica ipa-replica-install -U --skip-conncheck --principal admin --setup-ca --no-ntp
date
if docker diff freeipa-master | tee /dev/stderr | grep -Evf tests/docker-diff-ipa.out | grep . ; then
	exit 1
fi
echo OK $0.
