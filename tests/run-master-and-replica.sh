#!/bin/bash

set -e
set -x

if ! [ -f /sys/fs/cgroup/cgroup.controllers ] ; then
	echo "We expect to only run on cgroups v2 systems." >&2
	exit 1
fi

umask 0007

docker=${docker:-docker}

sudo=sudo

BASE=ipa1
VOLUME=${VOLUME:-/tmp/freeipa-test-$$/data}
if test "$VOLUME" != "${VOLUME#/}" ; then
	mkdir -p "$VOLUME"
fi

function setup_sudo() {
	if test "$VOLUME" == "${VOLUME#/}" ; then
		sudo="$docker run --rm -i --security-opt label=disable -v $VOLUME:/$VOLUME docker.io/library/busybox"
	else
		$docker run --rm -v $VOLUME:/data:Z docker.io/library/busybox touch /data/.test-permissions
		if echo test > $VOLUME/.test-permissions ; then
			sudo=
		else
			sudo=sudo
		fi
		rm -f $VOLUME/.test-permissions || :
	fi
}
setup_sudo

function wait_for_ipa_container() {
	set +x
	N="$1" ; shift
	set -e
	$docker logs -f "$N" &
	trap "kill $! 2> /dev/null || : ; trap - RETURN EXIT" RETURN EXIT
	EXIT_STATUS=999
	while true ; do
		sleep 10
		status=$( $docker inspect "$N" --format='{{.State.Status}}' )
		if [ "$status" == exited -o "$status" == stopped ] ; then
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
				$docker exec "$N" systemctl
				$docker exec "$N" systemctl status
				EXIT_STATUS=1
				break
			fi
		fi
	done
	date
	if [ "$EXIT_STATUS" -ne 0 ] ; then
		set +e
		if [ "$N" == "freeipa-replica" ] ; then
			$sudo tail -100 $VOLUME/var/log/ipareplica-install.log
		else
			$sudo tail -100 $VOLUME/var/log/ipaserver-install.log
		fi
		echo '---'
		$sudo tail -100 $VOLUME/var/log/ipa-server-run.log
		echo '---'
		$sudo tail -150 $VOLUME/var/log/ipaclient-install.log
		exit "$EXIT_STATUS"
	fi
	if ! $sudo grep '^2' $VOLUME/volume-version ; then
		exit 1
	fi
	if $docker diff "$N" | tee /dev/stderr | grep . ; then
		exit 1
	fi
	MACHINE_ID=$( $sudo cat $VOLUME/etc/machine-id )
	# Check that journal landed on volume and not in host's /var/log/journal
	$sudo ls -la $VOLUME/var/log/journal/$MACHINE_ID
	if [ -e /var/log/journal/$MACHINE_ID ] ; then
		ls -la /var/log/journal/$MACHINE_ID
		exit 1
	fi
}

function run_ipa_container() {
	set +x
	IMAGE="$1" ; shift
	N="$1" ; shift
	set -e
	date
	HOSTNAME=ipa.example.test
	if [ "$N" == "freeipa-replica" ] ; then
		HOSTNAME=replica.example.test
		if test "$VOLUME" == "${VOLUME#/}" ; then
			VOLUME=$VOLUME-$$-replica
			$docker volume create $VOLUME
		else
			VOLUME=/tmp/freeipa-test-$$/data-replica
			mkdir -p $VOLUME
		fi
		setup_sudo
	fi
	OPTS=
	if [ "${docker%podman}" = "$docker" ] ; then
		# if it is not podman, it is docker
		if $docker info --format '{{ .ClientInfo.Context }}' | grep rootless ; then
			OPTS="--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw"
		else
			# docker with userns remapping enabled
			:
		fi
		OPTS="$OPTS --sysctl net.ipv6.conf.all.disable_ipv6=0"
	fi
	if [ -n "$seccomp" ] ; then
		OPTS="$OPTS --security-opt seccomp=$seccomp"
	fi
	if [ "$(id -u)" != 0 -a "$docker" == podman -a "$replica" != none ] ; then
		OPTS="$OPTS --network=bridge"
	fi
	OPTS="$OPTS -h $HOSTNAME"
	(
	set -x
	umask 0
	$docker run -d --name "$N" $OPTS \
		-v $VOLUME:/data:Z $DOCKER_RUN_OPTS \
		-e PASSWORD=Secret123 "$IMAGE" "$@"
	)
	wait_for_ipa_container "$N" "$@"
}

function check_uids_gids() {
	local N="$1" ; shift
	set -x
	! $docker exec -w /data "$N" \
		find . -xdev \( -uid +0 -o -gid +0 \) -exec stat --format="%u %g %n" {} \; 2> /dev/null \
			| grep -v -E '^(0|65534|389|289|288|17|285|25|225|59|325) (0|65534|389|289|288|17|285|25|22|88|190|225|207|59|325) '
}

IMAGE="$1"

DOCKER_RUN_OPTS="--dns=127.0.0.1"
if [ "$readonly" == "--read-only" ] ; then
	DOCKER_RUN_OPTS="$DOCKER_RUN_OPTS --read-only"
fi

skip_opts=
if [ "$docker" == docker ] \
	&& $docker info --format '{{ .ClientInfo.Context }}' | grep -q rootless ; then
	skip_opts=--skip-mem-check
fi


fresh_install=true
if $sudo test -f "$VOLUME/build-id" ; then
	# If we were given already populated volume, just run the container
	fresh_install=false
	run_ipa_container $IMAGE freeipa-master exit-on-finished
else
	# Initial setup of the FreeIPA server
	dns_opts="--auto-reverse --allow-zone-overlap"
	if [ "$replica" = 'none' ] ; then
		dns_opts=""
	fi
	run_ipa_container $IMAGE freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders $dns_opts $skip_opts --no-ntp $ca

	if [ -n "$ca" ] ; then
		$docker rm -f freeipa-master
		date
		cat tests/generate-external-ca.sh | $sudo tee $VOLUME/generate-external-ca.sh > /dev/null
		$sudo chmod a+x $VOLUME/generate-external-ca.sh
		$docker run --rm -v $VOLUME:/data:Z --entrypoint /data/generate-external-ca.sh "$IMAGE"
		# For external CA, provide the certificate for the second stage
		run_ipa_container $IMAGE freeipa-master exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders $skip_opts --no-ntp \
			--external-cert-file=/data/ipa.crt --external-cert-file=/data/ca.crt
	fi
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
$sudo mv $VOLUME/build-id $VOLUME/build-id.initial
uuidgen | $sudo tee $VOLUME/build-id
$sudo touch -r $VOLUME/build-id.initial $VOLUME/build-id
run_ipa_container $IMAGE freeipa-master

# Wait for the services to start to the point when SSSD is operational
for i in $( seq 1 20 ) ; do
	if $docker exec freeipa-master id admin 2> /dev/null ; then
		break
	fi
	if [ "$((i % 5))" == 1 ] ; then
		echo "Waiting for SSSD in the container to start ..."
	fi
	sleep 5
done
(
set -x
seq 60 -1 0 | while read i ; do $docker exec freeipa-master dig +short ipa.example.test | tee /dev/stderr | grep -q '\.*\..*\.' && break ; sleep 5 ; [ $i == 0 ] && false ; done
seq 60 -1 0 | while read i ; do $docker exec freeipa-master dig +short -t srv _ldap._tcp.example.test | tee /dev/stderr | grep -Fq '0 100 389 ipa.example.test.' && break ; sleep 5 ; [ $i == 0 ] && false ; done

$docker exec freeipa-master bash -c 'yes Secret123 | kinit admin'
$docker exec freeipa-master ipa user-add --first Bob --last Nowak bob$$
$docker exec freeipa-master id bob$$

if $fresh_install ; then
	$docker exec freeipa-master ipa-adtrust-install -a Secret123 --netbios-name=EXAMPLE -U
	$docker exec freeipa-master ipa-kra-install -p Secret123 -U
	$docker exec freeipa-master ipa-dns-install -U --dnssec-master --no-forwarders
fi
)

check_uids_gids freeipa-master

if [ "$replica" = 'none' ] ; then
	echo OK $0.
	exit
fi

# Setup replica
MASTER_IP=$( $docker inspect --format '{{ .NetworkSettings.IPAddress }}' freeipa-master )
DOCKER_RUN_OPTS="--dns=$MASTER_IP"
if [ "$readonly" == "--read-only" ] ; then
	DOCKER_RUN_OPTS="$DOCKER_RUN_OPTS --read-only"
fi
if [ "$docker" != "sudo podman" -a "$docker" != "podman" ] ; then
	DOCKER_RUN_OPTS="--link freeipa-master:ipa.example.test $DOCKER_RUN_OPTS"
fi
SETUP_CA=--setup-ca
if [ $(( $RANDOM % 2 )) == 0 ] ; then
	SETUP_CA=
fi
run_ipa_container $IMAGE freeipa-replica no-exit ipa-replica-install -U --principal admin $SETUP_CA $skip_opts --no-ntp
date
if $docker diff freeipa-master | tee /dev/stderr | grep . ; then
	exit 1
fi
if [ -z "$SETUP_CA" ] ; then
	$docker exec freeipa-replica ipa-ca-install -p Secret123
	$docker exec freeipa-replica systemctl is-system-running
fi
check_uids_gids freeipa-master
check_uids_gids freeipa-replica
echo OK $0.
