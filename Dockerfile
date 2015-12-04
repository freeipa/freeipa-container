# Clone from the Fedora 23 image
FROM fedora:23

MAINTAINER Jan Pazdziora

# Install FreeIPA server
RUN mkdir -p /run/lock && dnf install -y freeipa-server freeipa-server-dns bind bind-dyndb-ldap perl 'perl(bigint)' patch && dnf clean all
ADD ticket-5269.patch /root/ticket-5269.patch
RUN patch /usr/lib/python2.7/site-packages/ipaserver/install/cainstance.py < /root/ticket-5269.patch && python -c 'import ipaserver.install.cainstance'

RUN for d in systemd/system tmpfiles.d ; do ( cd /etc/$d && grep -R -L '\.include /usr/lib/systemd/system' | while read i ; do rm -f /usr/lib/$d/$i ; mkdir -p $( dirname /usr/lib/$d/$i ) ; mv -v $i /usr/lib/$d/$i ; done ) ; done
RUN ( cd /etc/systemd/system && find . -name '*.service' | while read i ; do mkdir -p /usr/lib/systemd/system && mv $i /usr/lib/systemd/system/$i.d/abc.conf && sed -i '\|include /usr/lib/systemd/system|d' /usr/lib/systemd/system/$i.d/abc.conf ; done )
ADD dbus.service /usr/lib/systemd/system/dbus.service.d/containerized.conf
ADD httpd.service /usr/lib/systemd/system/httpd.service.d/pidfile.conf

ADD systemctl /usr/bin/systemctl
ADD systemctl-socket-daemon /usr/bin/systemctl-socket-daemon

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first
ADD ipa-volume-upgrade-0.5-0.6 /usr/sbin/ipa-volume-upgrade-0.5-0.6

RUN chmod -v +x /usr/bin/systemctl /usr/bin/systemctl-socket-daemon /usr/sbin/ipa-server-configure-first /usr/sbin/ipa-volume-upgrade-0.5-0.6

RUN groupadd -g 389 dirsrv ; useradd -u 389 -g 389 -c 'DS System User' -d '/var/lib/dirsrv' --no-create-home -s '/sbin/nologin' dirsrv
RUN groupadd -g 288 kdcproxy ; useradd -u 288 -g 288 -c 'IPA KDC Proxy User' -d '/var/lib/kdcproxy' -s '/sbin/nologin' kdcproxy

ADD volume-data-list /etc/volume-data-list
ADD volume-data-mv-list /etc/volume-data-mv-list
RUN set -e ; cd / ; mkdir /data-template ; cat /etc/volume-data-list | while read i ; do echo $i ; if [ -e $i ] ; then tar cf - .$i | ( cd /data-template && tar xf - ) ; fi ; mkdir -p $( dirname $i ) ; if [ "$i" == /var/log/ ] ; then mv /var/log /var/log-removed ; else rm -rf $i ; fi ; ln -sf /data${i%/} ${i%/} ; done
ADD volume-data-autoupdate /etc/volume-data-autoupdate
RUN rm -rf /var/log-removed
RUN sed -i 's!^d /var/log.*!L /var/log - - - - /data/var/log!' /usr/lib/tmpfiles.d/var.conf
# Workaround 1286602
RUN mv /usr/lib/tmpfiles.d/journal-nocow.conf /usr/lib/tmpfiles.d/journal-nocow.conf.disabled
RUN mv /data-template/etc/dirsrv/schema /usr/share/dirsrv/schema && ln -s /usr/share/dirsrv/schema /data-template/etc/dirsrv/schema
RUN echo 0.6 > /etc/volume-version
RUN uuidgen > /data-template/build-id

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp 7389 9443 9444 9445

VOLUME /data

ENTRYPOINT /usr/sbin/ipa-server-configure-first
