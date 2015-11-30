# Clone from the Fedora 23 image
FROM fedora:23

MAINTAINER Jan Pazdziora

# Install FreeIPA server
RUN dnf install -y freeipa-server freeipa-server-dns bind bind-dyndb-ldap perl 'perl(bigint)' patch && dnf clean all
ADD ticket-5269.patch /root/ticket-5269.patch
RUN patch /usr/lib/python2.7/site-packages/ipaserver/install/cainstance.py < /root/ticket-5269.patch && python -c 'import ipaserver.install.cainstance'

ADD dbus.service /etc/systemd/system/dbus.service
RUN ln -sf dbus.service /etc/systemd/system/messagebus.service
ADD httpd.service /etc/systemd/system/httpd.service

ADD systemctl /usr/bin/systemctl
ADD systemctl-socket-daemon /usr/bin/systemctl-socket-daemon

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first

RUN chmod -v +x /usr/bin/systemctl /usr/bin/systemctl-socket-daemon /usr/sbin/ipa-server-configure-first

RUN groupadd -g 389 dirsrv ; useradd -u 389 -g 389 -c 'DS System User' -d '/var/lib/dirsrv' --no-create-home -s '/sbin/nologin' dirsrv

ADD volume-data-list /etc/volume-data-list
ADD volume-data-mv-list /etc/volume-data-mv-list
RUN set -e ; cd / ; mkdir /data-template ; cat /etc/volume-data-list | while read i ; do echo $i ; if [ -e $i ] ; then tar cf - .$i | ( cd /data-template && tar xf - ) ; fi ; mkdir -p $( dirname $i ) ; if [ "$i" == /var/log/ ] ; then mv /var/log /var/log-removed ; else rm -rf $i ; fi ; ln -sf /data${i%/} ${i%/} ; done
ADD volume-data-autoupdate /etc/volume-data-autoupdate
RUN rm -rf /var/log-removed
RUN sed -i 's!^d /var/log.*!L /var/log - - - - /data/var/log!' /usr/lib/tmpfiles.d/var.conf
# Workaround 1286602
RUN mv /usr/lib/tmpfiles.d/journal-nocow.conf /usr/lib/tmpfiles.d/journal-nocow.conf.disabled
RUN mv /data-template/etc/dirsrv/schema /usr/share/dirsrv/schema && ln -s /usr/share/dirsrv/schema /data-template/etc/dirsrv/schema
RUN echo 0.5 > /etc/volume-version
RUN uuidgen > /data-template/build-id

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp 7389 9443 9444 9445

VOLUME /data

ENTRYPOINT /usr/sbin/ipa-server-configure-first
