# Clone from the Fedora 23 image
FROM fedora:23
MAINTAINER Jan Pazdziora
FROM centos:7

RUN yum install -y \
	bind \
	bind-dyndb-ldap \
	ipa-server \
	ipa-server-dns \
	systemd \
	&& ( \
		cd /lib/systemd/system/sysinit.target.wants/; \
		for i in *; do \
			if [ "$i" != "systemd-tmpfiles-setup.service" ]; then \
				rm -f $i; \
			fi \
		done \
	) \
	&& rm -f /lib/systemd/system/multi-user.target.wants/* \
	&& rm -f /etc/systemd/system/*.wants/* \
	&& rm -f /lib/systemd/system/local-fs.target.wants/* \
	&& rm -f /lib/systemd/system/sockets.target.wants/*udev* \
	&& rm -f /lib/systemd/system/sockets.target.wants/*initctl* \
	&& rm -f /lib/systemd/system/anaconda.target.wants/* \
	&& rm -f /lib/systemd/system/basic.target.wants/* \
	&& rm -f /lib/systemd/system/graphical.target.wants/* \
	&& ln -vf /lib/systemd/system/multi-user.target /lib/systemd/system/default.target

ENV TERM xterm
ENV LANG en_US.UTF-8

# systemd needs a different stop signal
STOPSIGNAL SIGRTMIN+3

COPY init-data ipa-server-configure-first ipa-server-status-check exit-with-status ipa-volume-upgrade-* /usr/sbin/
RUN chmod -v +x /usr/sbin/init-data /usr/sbin/ipa-server-configure-first /usr/sbin/ipa-server-status-check /usr/sbin/exit-with-status /usr/sbin/ipa-volume-upgrade-*
COPY ipa-server-configure-first.service ipa-server-upgrade.service ipa-server-update-self-ip-address.service /usr/lib/systemd/system/

RUN systemctl enable ipa-server-configure-first.service

RUN groupadd -g 389 dirsrv ; useradd -u 389 -g 389 -c 'DS System User' -d '/var/lib/dirsrv' --no-create-home -s '/sbin/nologin' dirsrv
RUN groupadd -g 288 kdcproxy ; useradd -u 288 -g 288 -c 'IPA KDC Proxy User' -d '/var/lib/kdcproxy' -s '/sbin/nologin' kdcproxy

COPY volume-data-list volume-data-mv-list volume-data-autoupdate /etc/
RUN set -e ; cd / ; mkdir /data-template ; cat /etc/volume-data-list | while read i ; do echo $i ; if [ -e $i ] ; then tar cf - .$i | ( cd /data-template && tar xf - ) ; fi ; mkdir -p $( dirname $i ) ; if [ "$i" == /var/log/ ] ; then mv /var/log /var/log-removed ; else rm -rf $i ; fi ; ln -sf /data${i%/} ${i%/} ; done
RUN rm -rf /var/log-removed \
	&& sed -i 's!^d /var/log.*!L /var/log - - - - /data/var/log!' /usr/lib/tmpfiles.d/var.conf \
	&& mv /data-template/etc/dirsrv/schema /usr/share/dirsrv/schema \
	&& ln -s /usr/share/dirsrv/schema /data-template/etc/dirsrv/schema \
	&& rm -f /data-template/var/lib/systemd/random-seed \
	&& echo 1.1 > /etc/volume-version \
	&& uuidgen > /data-template/build-id

ENV container docker

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp 7389 9443 9444 9445

VOLUME [ "/data" ]

ENTRYPOINT [ "/sbin/init-data" ]
