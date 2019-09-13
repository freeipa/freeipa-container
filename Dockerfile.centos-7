# Clone from the CentOS 7
FROM registry.centos.org/centos:7

MAINTAINER Jan Pazdziora
# Moving groupadd before freeipa installation to ensure uid and guid will be same
RUN groupadd -g 288 kdcproxy ; useradd -u 288 -g 288 -c 'IPA KDC Proxy User' -d '/var/lib/kdcproxy' -s '/sbin/nologin' kdcproxy
RUN groupadd -g 289 ipaapi; useradd -u 289 -g 289 -c 'IPA Framework User' -r -d / -s '/sbin/nologin' ipaapi

# Workaround 1615948
RUN ln -s /bin/false /usr/sbin/systemd-machine-id-setup
RUN yum upgrade -y && yum install -y ipa-server ipa-server-dns ipa-server-trust-ad patch && yum clean all

# debug: RUN test $( getent passwd | grep -E "^(dirsrv:x:389|ipaapi:x:289|kdcproxy:x:288|pkiuser:x:17):" | wc -l ) -eq 4

# Container image which runs systemd
# debug: RUN test -f /etc/machine-id && ! test -s /etc/machine-id
# debug: RUN test -z "$container"
ENV container oci

# Establish reasonably low open files limit in the container
RUN echo "DefaultLimitNOFILE=1024" >> /etc/systemd/system.conf

ENTRYPOINT [ "/usr/sbin/init" ]
STOPSIGNAL RTMIN+3
# test-addon: VOLUME [ "/var/log/journal" ]
# test: systemd-container-failed.sh network.service TRAVIS:sys-fs-fuse-connections.mount var-lib-nfs-rpc_pipefs.mount

# Minimize the systemd setup
RUN find /etc/systemd/system /usr/lib/systemd/system/{basic,multi-user,sysinit}.target.wants -type l | xargs rm -v
COPY patches/minimal-centos-7.patch /root/
RUN patch --verbose -p0 --fuzz=0 < /root/minimal-centos-7.patch
# debug: RUN ! find /etc/systemd/system /usr/lib/systemd/system/{basic,multi-user,sysinit}.target.wants /etc/tmpfiles.d -type f | grep .

COPY container-ipa.target /usr/lib/systemd/system/
RUN systemctl set-default container-ipa.target
RUN rmdir -v /etc/systemd/system/multi-user.target.wants \
	&& mkdir /etc/systemd/system/container-ipa.target.wants \
	&& ln -s /etc/systemd/system/container-ipa.target.wants /etc/systemd/system/multi-user.target.wants
RUN rm /var/lib/systemd/random-seed
RUN echo 0123456789abcdef0000000000000000 > /etc/machine-id && systemd-tmpfiles --remove --create && echo -n > /etc/machine-id
# debug: RUN ! test -f /var/lib/systemd/random-seed
# test-addon: VOLUME [ "/var/log/journal" ]
# test: systemd-container-diff.sh list-dependencies-centos-7.out docker-diff-minimal-centos-7.exceptions docker-diff-minimal-centos-7.out

# Prepare for basic ipa-server-install in container
# Address failing rhel-domainname.service in the ipa-client-install step
RUN mv /usr/bin/domainname /usr/bin/domainname.orig
ADD hostnamectl-wrapper /usr/bin/domainname

COPY patches/ipa-rhel-7.patch /root
RUN set -o pipefail ; patch --verbose -p0 --fuzz=0 < /root/ipa-rhel-7.patch | tee /dev/stderr | sed -n 's/^patching file //;T;/\.py$/p' | xargs python -m compileall
# test-addon: VOLUME [ "/var/log/journal" ]
## # test: systemd-container-ipa-server-install.sh

# Move configuration and data to data volume
COPY patches/ipa-data-centos-7.patch /root
RUN set -o pipefail ; patch --verbose -p0 --fuzz=0 < /root/ipa-data-centos-7.patch | tee /dev/stderr | sed -n 's/^patching file //;T;/\.py$/p' | xargs python -m compileall

RUN mv /usr/sbin/ipa-join /usr/sbin/ipa-join.orig
COPY ipa-join /usr/sbin/ipa-join

COPY utils/prepare-volume-template utils/populate-volume-from-template utils/extract-rpm-upgrade-scriptlets /usr/local/bin/
COPY volume-data-list volume-tmp-list volume-data-autoupdate /etc/
RUN /usr/local/bin/prepare-volume-template /etc/volume-data-list /data
RUN /usr/local/bin/prepare-volume-template /etc/volume-tmp-list /tmp
RUN /usr/local/bin/extract-rpm-upgrade-scriptlets

RUN echo 2.0 > /etc/volume-version
VOLUME [ "/tmp", "/run", "/data", "/var/log/journal" ]

COPY init-data-minimal /usr/local/sbin/init
ENTRYPOINT [ "/usr/local/sbin/init" ]
# test: systemd-container-ipa-server-install-data.sh docker-diff-minimal-centos-7.out

# Configure master/replica upon the first invocation
COPY init-data /usr/local/sbin/init
COPY ipa-server-configure-first exit-with-status ipa-volume-upgrade-* /usr/sbin/
COPY ipa-server-configure-first.service ipa-server-upgrade.service ipa-server-update-self-ip-address.service /usr/lib/systemd/system/
RUN ln -sv /usr/lib/systemd/system/ipa-server-configure-first.service /data-template/etc/systemd/system/container-ipa.target.wants/ipa-server-configure-first.service
COPY exit-via-chroot.conf /usr/lib/systemd/system/systemd-poweroff.service.d/

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp

RUN uuidgen > /data-template/build-id

# Invocation:
# docker run -ti -v /sys/fs/cgroup:/sys/fs/cgroup:ro --tmpfs /run --tmpfs /tmp -v /opt/ipa-data:/data:Z -h ipa.example.test ${NAME} [ options ]

# Atomic specific bits
COPY install.sh uninstall.sh /bin/
COPY atomic-install-help /usr/share/ipa/

# For atomic, we run INSTALL --privileged but install.sh will start another unprivileged container.
# We do it this way to be able to set hostname for the unprivileged container.
LABEL install 'docker run -ti --rm --privileged -v /:/host -e HOST=/host -e DATADIR=/var/lib/${NAME} -e NAME=${NAME} -e IMAGE=${IMAGE} ${IMAGE} /bin/install.sh'
LABEL run 'docker run ${RUN_OPTS} --name ${NAME} -v /var/lib/${NAME}:/data:Z -v /sys/fs/cgroup:/sys/fs/cgroup:ro --tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro ${IMAGE}'
LABEL RUN_OPTS_FILE '/var/lib/${NAME}/docker-run-opts'
LABEL stop 'docker stop ${NAME}'
LABEL uninstall 'docker run --rm --privileged -v /:/host -e HOST=/host -e DATADIR=/var/lib/${NAME} ${IMAGE} /bin/uninstall.sh'

LABEL summary="Identity Management (IdM) for Linux provides centralized \
management of identities and policies for Atomic Host"
LABEL description="IPA is an integrated solution to provide centrally managed \
Identity (users, hosts, services), Authentication (SSO, 2FA), and \
Authorization (host access control, SELinux user roles, services). The \
solution provides features for further integration with Linux based clients \
(SUDO, automount) and integration with Active Directory based infrastructures \
(Trusts)."
LABEL io.k8s.display-name="Identity Management (IdM) for Linux"
LABEL io.k8s.description="IPA is an integrated solution to provide centrally \
managed Identity (users, hosts, services), Authentication (SSO, 2FA), and \
Authorization (host access control, SELinux user roles, services). The \
solution provides features for further integration with Linux based clients \
(SUDO, automount) and integration with Active Directory based infrastructures \
(Trusts)."
