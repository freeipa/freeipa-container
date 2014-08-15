# Clone from the Fedora 20 image
FROM fedora:20

MAINTAINER Jan Pazdziora

# Install FreeIPA server
RUN yum install -y freeipa-server bind bind-dyndb-ldap perl && yum clean all
RUN mkdir -p /run/lock

# To be able to debug
RUN yum install -y openssh-server strace lsof && yum clean all
RUN echo 'root:jezek' | chpasswd
RUN echo set -o vi >> /etc/bashrc

ADD dbus.service /etc/systemd/system/dbus.service
RUN ln -sf dbus.service /etc/systemd/system/messagebus.service

ADD runuser-pp /usr/sbin/runuser-pp
ADD systemctl /usr/bin/systemctl
ADD systemctl-socket-daemon /usr/bin/systemctl-socket-daemon

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first

RUN chmod -v +x /usr/bin/systemctl /usr/bin/systemctl-socket-daemon /usr/sbin/ipa-server-configure-first /usr/sbin/runuser-pp

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp

ENTRYPOINT /usr/sbin/ipa-server-configure-first
