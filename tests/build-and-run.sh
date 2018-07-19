#!/bin/bash

set -e
set -x

if ! grep -F "Dockerfile.$dockerfile" <( echo "$BUILD_DOCKERFILES" ) ; then
	echo "Skipping, Dockerfile.$dockerfile not modified."
	exit
fi

docker build -t local/freeipa-server -f Dockerfile.$dockerfile .
mkdir data
docker run $privileged -h ipa.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data:/data \
	-e PASSWORD=Secret123 local/freeipa-server \
	exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp $ca
if [ -n "$ca" ] ; then
	sudo tests/generate-external-ca.sh data
	docker run $privileged -h ipa.example.test \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		-v $(pwd)/data:/data \
		-e PASSWORD=Secret123 local/freeipa-server \
		exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp \
			--external-cert-file=/data/ipa.crt --external-cert-file=/data/ca.crt
fi
