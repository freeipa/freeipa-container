#!/bin/bash

set -e
set -x

if [ -f /sys/fs/cgroup/cgroup.controllers ] ; then
	OPTS="--kubelet-arg=cgroup-driver=systemd"
else
	patch tests/freeipa-k3s.yaml < tests/freeipa-k3s.yaml.cgroups-v1.patch
	patch tests/freeipa-replica-k3s.yaml < tests/freeipa-replica-k3s.yaml.cgroups-v1.patch
fi
if [ -e /var/run/cri-dockerd.sock ] ; then
	OPTS="$OPTS --container-runtime-endpoint=unix:///var/run/cri-dockerd.sock --kubelet-arg=allowed-unsafe-sysctls=net.ipv6.conf.all.disable_ipv6"
	patch tests/freeipa-k3s.yaml < tests/freeipa-k3s.yaml.docker.patch
	patch tests/freeipa-replica-k3s.yaml < tests/freeipa-k3s.yaml.docker.patch
else
	patch tests/freeipa-k3s.yaml < tests/freeipa-k3s.yaml.shm.patch
	patch tests/freeipa-replica-k3s.yaml < tests/freeipa-k3s.yaml.shm.patch
fi
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 $OPTS --egress-selector-mode=disabled
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
( set +x ; while true ; do if kubectl get nodes | tee /dev/stderr | grep -q '\bReady\b' ; then break ; else sleep 5 ; fi ; done )
if [ -n "$2" ] ; then
	sudo k3s ctr images import "$2"
fi
kubectl get pods --all-namespaces
( set +x ; while ! kubectl get serviceaccount/default ; do sleep 5 ; done )
if [ -f /sys/fs/cgroup/cgroup.controllers ] ; then
	# Make local-path provisioner on userns remapped docker setup on cgroups v2 work
	# -- the pods of the cluster run remapped as well
	sudo mkdir -p /var/lib/rancher/k3s/storage
	sudo chown $( id -u ) /var/lib/rancher/k3s/storage
fi
kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-k3s.yaml )
( set +x ; while kubectl get pod/freeipa-server | tee /dev/stderr | grep -Eq '\bPending\b|\bContainerCreating\b' ; do sleep 5 ; done )
if ! kubectl get pod/freeipa-server | grep -q '\bRunning\b' ; then
	kubectl describe pod/freeipa-server
	kubectl logs pod/freeipa-server
	exit 1
fi
( set +x ; for i in $( seq 1 10 ) ; do kubectl logs pod/freeipa-server > /dev/null && break ; sleep 3 ; done )
kubectl logs -f pod/freeipa-server &
MASTER_LOGS_PID=$!
trap "kill $MASTER_LOGS_PID 2> /dev/null || : ; trap - EXIT" EXIT
( set +x ; while true ; do if kubectl get pod/freeipa-server | grep -q '\b1/1\b' ; then kill $MASTER_LOGS_PID ; break ; else sleep 5 ; fi ; done )
kubectl describe pod/freeipa-server
PV_DIR=$( kubectl get pvc/freeipa-data-pvc -o 'jsonpath={.spec.volumeName}_{.metadata.namespace}_{.metadata.name}' )
ls -la /var/lib/rancher/k3s/storage/$PV_DIR
IPA_SERVER_HOSTNAME=$( kubectl exec pod/freeipa-server -- hostname -f )
if ! test -f /etc/resolv.conf.backup ; then
	sudo mv /etc/resolv.conf /etc/resolv.conf.backup
fi
sudo systemctl stop systemd-resolved.service || :
echo nameserver $( kubectl get -o=jsonpath='{.spec.clusterIP}' service freeipa-server-service ) | sudo tee /etc/resolv.conf
curl -Lk https://$IPA_SERVER_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
curl -H "Referer: https://$IPA_SERVER_HOSTNAME/ipa/ui/" -H 'Accept-Language: fr' -d '{"method":"i18n_messages","params":[[],{}]}' -k https://$IPA_SERVER_HOSTNAME/ipa/i18n_messages | grep -q utilisateur
echo Secret123 | kubectl exec -i pod/freeipa-server -- kinit admin
kill $MASTER_LOGS_PID 2> /dev/null || :
trap - EXIT

kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-replica-k3s.yaml )
( set +x ; while kubectl get pod/freeipa-replica | tee /dev/stderr | grep -Eq '\bPending\b|\bContainerCreating\b' ; do sleep 5 ; done )
if ! kubectl get pod/freeipa-replica | grep -q '\bRunning\b' ; then
	kubectl describe pod/freeipa-replica
	kubectl logs pod/freeipa-replica
	exit 1
fi
( set +x ; for i in $( seq 1 10 ) ; do kubectl logs pod/freeipa-replica > /dev/null && break ; sleep 3 ; done )
kubectl logs -f pod/freeipa-replica &
REPLICA_LOGS_PID=$!
trap "kill $REPLICA_LOGS_PID 2> /dev/null || : ; trap - EXIT" EXIT
( set +x ; while true ; do if kubectl get pod/freeipa-replica | grep -q '\b1/1\b' ; then kill $REPLICA_LOGS_PID ; break ; else sleep 5 ; fi ; done )
kubectl describe pod/freeipa-replica
PV_DIR=$( kubectl get pvc/freeipa-replica-pvc -o 'jsonpath={.spec.volumeName}_{.metadata.namespace}_{.metadata.name}' )
ls -la /var/lib/rancher/k3s/storage/$PV_DIR
IPA_REPLICA_HOSTNAME=$( kubectl exec pod/freeipa-replica -- hostname -f )
curl -Lk https://$IPA_REPLICA_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
curl -H "Referer: https://$IPA_REPLICA_HOSTNAME/ipa/ui/" -H 'Accept-Language: fr' -d '{"method":"i18n_messages","params":[[],{}]}' -k https://$IPA_REPLICA_HOSTNAME/ipa/i18n_messages | grep -q utilisateur
echo Secret123 | kubectl exec -i pod/freeipa-replica -- kinit admin
kill $REPLICA_LOGS_PID 2> /dev/null || :
trap - EXIT
