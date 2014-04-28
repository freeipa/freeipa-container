# Clone from the Fedora 20 image
FROM fedora:20
# Install FreeIPA server
RUN yum install -y freeipa-server
RUN mkdir -p /run/lock

# To be able to debug
RUN yum install -y openssh-server strace lsof
RUN echo 'root:jezek' | chpasswd
RUN echo set -o vi >> /etc/bashrc

ADD dbus.service /etc/systemd/system/dbus.service
RUN ln -sf dbus.service /etc/systemd/system/messagebus.service

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first
ADD systemctl /bin/systemctl
ADD systemctl-socket-daemon /bin/systemctl-socket-daemon

ENTRYPOINT /usr/sbin/ipa-server-configure-first
