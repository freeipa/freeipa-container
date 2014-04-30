# Clone from the Fedora 20 image
FROM fedora:20
# Install FreeIPA server
RUN yum install -y freeipa-server
RUN mkdir -p /run/lock

ADD dbus.service /etc/systemd/system/dbus.service
RUN ln -sf dbus.service /etc/systemd/system/messagebus.service

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first
ADD systemctl /bin/systemctl
ADD systemctl-socket-daemon /bin/systemctl-socket-daemon

ENTRYPOINT /usr/sbin/ipa-server-configure-first
