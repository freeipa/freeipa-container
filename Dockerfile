# Clone from the RHEL 7
FROM rhel7

MAINTAINER Jan Pazdziora

RUN yum swap -y -- remove fakesystemd -- install systemd systemd-libs && yum clean all

# Install FreeIPA client
RUN yum install -y ipa-client perl 'perl(Data::Dumper)' && yum clean all

ADD dbus.service /etc/systemd/system/dbus.service
RUN ln -sf dbus.service /etc/systemd/system/messagebus.service

ADD systemctl /usr/bin/systemctl
ADD ipa-client-configure-first /usr/sbin/ipa-client-configure-first

RUN chmod -v +x /usr/bin/systemctl /usr/sbin/ipa-client-configure-first

ENTRYPOINT /usr/sbin/ipa-client-configure-first
