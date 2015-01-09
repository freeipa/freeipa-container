# IPA-enrolled client in Docker

This repository contains the Dockerfile and associated assets for
building a Docker image from the official yum repo which can then be
easily IPA-enrolled to FreeIPA/IdM server, in another container or
on a host.

To build the image, run in the root of the repository:

    docker build -t freeipa-client .

To run the container and have it automatically enroll to an IPA
server, either link it to the freeipa-server container with alias
`ipa`, specify DNS nameservers explicitly with `--dns`, or have
your whole setup for the container based on its hostname and
the existing host configuration.

If your host's resolv.conf will allow the client to find the IPA
server for its domain, merely running

    docker run -h web.example.com -e PASSWORD=Secret123 -ti freeipa-client

will be enough. You can use `--dns` to point it to the correct
DNS server (possibly IPA server running DNS service).

Alternatively, use `--link` with alias `ipa` to point the client
container to IPA server container:

    docker run -h web.example.com --link freeipa-server-container:ipa -e PASSWORD=Secret123 -ti freeipa-client

The referenced server container must be running.

Since IPA-enrollment requires fully-qualified hostname and by
default docker run does not set FQDN, either specify it with
the `-h` options or run the container as privileged when it will
be allowed to change its own hostname, using IPA server's domain:

    docker run --privileged --link freeipa-server-container:ipa -e PASSWORD=Secret123 -ti freeipa-client

The first time this container runs, it invokes `ipa-client-install`
with the given admin password and configures itself against
the IPA server.

You can pass environment variable IPA_CLIENT_INSTALL_OPTS with
additional options that will be passed to ipa-client-install.

The `-ti` parameters are optional and are used for get a terminal
(useful for experimenting in the container).

The container can then be stopped and started:

    docker stop <the-container-id>
    docker start -ai <the-container-id>

# FreeIPA server in Docker

Checkout the `fedora-21`, `fedora-20`, `fedora-rawhide`, `rhel-7`,
`centos-7`, `rhel-7-upstream`, or `centos-7-upstream` branch
to get repository with the Dockerfile and associated assets for
building a FreeIPA/IdM server Docker image from the official yum
repo.

# Automated builds

From some of the branches in https://github.com/adelton/docker-freeipa,
images are automatically built into https://hub.docker.com/u/adelton/.

# Copyright 2014--2015 Jan Pazdziora

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
