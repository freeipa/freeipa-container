# Clone from the Fedora 23 image
FROM fedora:23

MAINTAINER Jan Pazdziora

RUN mkdir -p /run/lock && dnf install -y freeipa-server freeipa-server-dns bind bind-dyndb-ldap && dnf clean all

# Workaround https://fedorahosted.org/spin-kickstarts/ticket/60
RUN [ -L /etc/systemd/system/syslog.service ] && ! [ -f /etc/systemd/system/syslog.service ] && rm -f /etc/systemd/system/syslog.service

RUN echo 'd0a98590c74bfe36af0ce006f7b25fa60246aecb /etc/tmpfiles.d/opendnssec.conf' | sha1sum --quiet -c && mv -v /etc/tmpfiles.d/opendnssec.conf /usr/lib/tmpfiles.d/opendnssec.conf
RUN echo '0b6f62258de66f74328b0cf45cc937fae6a30e62 /etc/systemd/system/dbus.service' | sha1sum --quiet -c && rm -vf /etc/systemd/system/dbus.service
RUN echo '5a70f1f3db0608c156d5b6629d4cbc3b304fc045 /etc/systemd/system/sssd.service.d/journal.conf' | sha1sum --quiet -c && rm -vf /etc/systemd/system/sssd.service.d/journal.conf
RUN find /etc/systemd/system/* '!' -name '*.wants' | xargs rm -rvf
RUN for i in basic.target sysinit.target network.service netconsole.service ; do rm -f /usr/lib/systemd/system/$i && ln -s /dev/null /usr/lib/systemd/system/$i ; done

RUN echo LANG=C > /etc/locale.conf

RUN /sbin/ldconfig -X

COPY init-data ipa-server-configure-first ipa-server-status-check exit-with-status ipa-volume-upgrade-* /usr/sbin/
RUN chmod -v +x /usr/sbin/init-data /usr/sbin/ipa-server-configure-first /usr/sbin/ipa-server-status-check /usr/sbin/exit-with-status /usr/sbin/ipa-volume-upgrade-*
COPY container-ipa.target ipa-server-configure-first.service ipa-server-upgrade.service ipa-server-update-self-ip-address.service /usr/lib/systemd/system/
RUN rmdir -v /etc/systemd/system/multi-user.target.wants \
	&& mkdir /etc/systemd/system/container-ipa.target.wants \
	&& ln -s /etc/systemd/system/container-ipa.target.wants /etc/systemd/system/multi-user.target.wants

RUN systemctl set-default container-ipa.target
RUN systemctl enable ipa-server-configure-first.service

RUN mkdir -p /usr/lib/systemd/system/systemd-poweroff.service.d && ( echo '[Service]' ; echo 'ExecStartPre=/usr/bin/systemctl switch-root /usr /sbin/exit-with-status' ) > /usr/lib/systemd/system/systemd-poweroff.service.d/exit-via-chroot.conf

RUN groupadd -g 389 dirsrv ; useradd -u 389 -g 389 -c 'DS System User' -d '/var/lib/dirsrv' --no-create-home -s '/sbin/nologin' dirsrv
RUN groupadd -g 288 kdcproxy ; useradd -u 288 -g 288 -c 'IPA KDC Proxy User' -d '/var/lib/kdcproxy' -s '/sbin/nologin' kdcproxy

COPY volume-data-list volume-data-mv-list volume-data-autoupdate /etc/
RUN set -e ; cd / ; mkdir /data-template ; cat /etc/volume-data-list | while read i ; do echo $i ; if [ -e $i ] ; then tar cf - .$i | ( cd /data-template && tar xf - ) ; fi ; mkdir -p $( dirname $i ) ; if [ "$i" == /var/log/ ] ; then mv /var/log /var/log-removed ; else rm -rf $i ; fi ; ln -sf /data${i%/} ${i%/} ; done
RUN rm -rf /var/log-removed
RUN sed -i 's!^d /var/log.*!L /var/log - - - - /data/var/log!' /usr/lib/tmpfiles.d/var.conf
# Workaround 1286602
RUN mv /usr/lib/tmpfiles.d/journal-nocow.conf /usr/lib/tmpfiles.d/journal-nocow.conf.disabled
RUN mv /data-template/etc/dirsrv/schema /usr/share/dirsrv/schema && ln -s /usr/share/dirsrv/schema /data-template/etc/dirsrv/schema
RUN rm -f /data-template/var/lib/systemd/random-seed
RUN echo 1.1 > /etc/volume-version

RUN for i in /usr/lib/systemd/system/*-domainname.service ; do sed -i 's#^ExecStart=/#ExecStart=-/#' $i ; done

RUN sed -i 's/^UUID=/# UUID=/' /etc/fstab

ENV container docker

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp 7389 9443 9444 9445

VOLUME [ "/tmp", "/run", "/data" ]

ENTRYPOINT [ "/usr/sbin/init-data" ]
RUN uuidgen > /data-template/build-id

LABEL INSTALL "docker run -ti -v /sys/fs/cgroup:/sys/fs/cgroup:ro -v /opt/ipa-data:/data:Z -h ipa.example.test ${NAME} exit-on-finished"
LABEL RUN "docker run -ti -v /sys/fs/cgroup:/sys/fs/cgroup:ro -v /opt/ipa-data:/data:Z -h ipa.example.test ${NAME}"
