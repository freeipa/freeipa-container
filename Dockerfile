# Clone from the Fedora 23 image
FROM fedora:23

MAINTAINER Jan Pazdziora

RUN mkdir -p /run/lock && dnf install -y freeipa-server freeipa-server-dns bind bind-dyndb-ldap 'perl(bigint)' patch && dnf clean all
ADD ticket-5269.patch /root/ticket-5269.patch
RUN patch /usr/lib/python2.7/site-packages/ipaserver/install/cainstance.py < /root/ticket-5269.patch && python -c 'import ipaserver.install.cainstance'

# Workaround https://fedorahosted.org/spin-kickstarts/ticket/60
RUN [ -L /etc/systemd/system/syslog.service ] && ! [ -f /etc/systemd/system/syslog.service ] && rm -f /etc/systemd/system/syslog.service
RUN for d in systemd/system tmpfiles.d ; do ( cd /etc/$d && grep -R -L '\.include /usr/lib/systemd/system' | while read i ; do rm -f /usr/lib/$d/$i ; mkdir -p $( dirname /usr/lib/$d/$i ) ; mv -v $i /usr/lib/$d/$i ; done ) ; done
RUN ( cd /etc/systemd/system && find . -name '*.service' | while read i ; do mkdir -p /usr/lib/systemd/system/$i.d && mv $i /usr/lib/systemd/system/$i.d/abc.conf && sed -i '\|include /usr/lib/systemd/system|d' /usr/lib/systemd/system/$i.d/abc.conf ; done )

RUN for i in swap.target local-fs.target rhel-autorelabel-mark.service systemd-update-done.service rpcbind.socket rhel-dmesg.service systemd-user-sessions.service network.service rhsmcertd.service proc-fs-nfsd.mount nfs-config.service nfs-client.target systemd-hwdb-update.service ldconfig.service slices.target dnf-makecache.service fedora-autorelabel-mark.service ; do rm -f /usr/lib/systemd/system/$i ; ln -s /dev/null /usr/lib/systemd/system/$i ; done
RUN /sbin/ldconfig -X

COPY init-data ipa-server-configure-first ipa-volume-upgrade-* /usr/sbin/
RUN chmod -v +x /usr/sbin/init-data /usr/sbin/ipa-server-configure-first /usr/sbin/ipa-volume-upgrade-*
COPY ipa-server-configure-first.service ipa-server-upgrade.service ipa-server-update-self-ip-address.service /usr/lib/systemd/system/
RUN systemctl enable ipa-server-configure-first.service

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
RUN echo 1.0 > /etc/volume-version

RUN for i in /usr/lib/systemd/system/*-domainname.service ; do sed -i 's#^ExecStart=/#ExecStart=-/#' $i ; done

RUN sed -i 's/^UUID=/# UUID=/' /etc/fstab

ENV container docker

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp 7389 9443 9444 9445

VOLUME [ "/tmp", "/run", "/data" ]

ENTRYPOINT [ "/usr/sbin/init-data" ]
RUN uuidgen > /data-template/build-id

LABEL RUN "docker run -ti -v /sys/fs/cgroup:/sys/fs/cgroup:ro -v /opt/ipa-data:/data:Z -h ipa.example.test ${NAME}"
