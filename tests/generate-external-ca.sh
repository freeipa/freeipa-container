#!/bin/bash

set -e
set -x

DATA="${1:-/data}"
NSSDB=/tmp/nssdb-$RANDOM
mkdir -p $NSSDB
rm -rf $NSSDB/*
certutil -N -d $NSSDB --empty-password
echo -e "y\n\n\n$RANDOM\n\n" | certutil -S -n "IPA ROOTCA certificate" -s "cn=CAcert" -x -t "CT,," -m 1000 -v 120 -d $NSSDB -z /etc/hostname -2 --keyUsage=certSigning --extSKID
certutil -L -d $NSSDB -n 'IPA ROOTCA certificate' -a > "$DATA"/ca.crt
echo -e "$RANDOM\nn\n" | certutil -C -m 2346 -i "$DATA"/ipa.csr -o "$DATA"/ipa.crt -c 'IPA ROOTCA certificate' -d $NSSDB -a --extSKID
