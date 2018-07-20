#!/bin/bash

set -e
set -x

if ! grep -F "Dockerfile.$dockerfile" <( echo "$BUILD_DOCKERFILES" ) ; then
	echo "Skipping, Dockerfile.$dockerfile not modified."
	exit
fi

date
docker build -t local/freeipa-server -f Dockerfile.$dockerfile .
mkdir data
date
docker run $privileged -h ipa.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data:/data \
	-e PASSWORD=Secret123 local/freeipa-server \
	exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp $ca
if [ -n "$ca" ] ; then
	date
	sudo tests/generate-external-ca.sh data
	date
	docker run $privileged -h ipa.example.test \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		-v $(pwd)/data:/data \
		-e PASSWORD=Secret123 local/freeipa-server \
		exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp \
			--external-cert-file=/data/ipa.crt --external-cert-file=/data/ca.crt
fi
date
docker run $privileged -h ipa.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data:/data \
	local/freeipa-server \
	exit-on-finished
date
echo "RUN uuidgen > /data-template/build-id" >> Dockerfile.$dockerfile
echo data >> .dockerignore
docker build -t local/freeipa-server -f Dockerfile.$dockerfile .
date
docker run $privileged -h ipa.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data:/data \
	local/freeipa-server \
	exit-on-finished
