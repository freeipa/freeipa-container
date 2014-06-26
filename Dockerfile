# Clone from the RHEL 7
FROM rhel7:0

MAINTAINER Jan Pazdziora

RUN yum swap -y -- remove fakesystemd -- install systemd systemd-libs && yum clean all

# Install FreeIPA server
RUN yum install -y ipa-server bind bind-dyndb-ldap perl && yum clean all
RUN mkdir -p /run/lock

ADD dbus.service /etc/systemd/system/dbus.service
RUN ln -sf dbus.service /etc/systemd/system/messagebus.service

ADD systemctl /usr/bin/systemctl
ADD systemctl-socket-daemon /usr/bin/systemctl-socket-daemon

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first

RUN chmod -v +x /usr/bin/systemctl /usr/bin/systemctl-socket-daemon /usr/sbin/ipa-server-configure-first

EXPOSE 53/udp 80 443 389 636 88 464 88/udp 464/udp 123/udp

ENTRYPOINT /usr/sbin/ipa-server-configure-first
