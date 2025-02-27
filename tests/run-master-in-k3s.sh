#!/bin/bash

set -e
set -x

if ! [ -f /sys/fs/cgroup/cgroup.controllers ] ; then
	echo "We expect to only run on cgroups v2 systems." >&2
	exit 1
fi

OPTS=
if [ -e /var/run/docker.sock ] ; then
	OPTS="$OPTS --docker --kubelet-arg=allowed-unsafe-sysctls=net.ipv6.conf.all.disable_ipv6"
	patch tests/freeipa-k3s.yaml < tests/freeipa-k3s.yaml.docker.patch
	patch tests/freeipa-replica-k3s.yaml < tests/freeipa-k3s.yaml.docker.patch
fi
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig ~/.kube/config $OPTS
sudo chown -R $( id -u ):$( id -g ) ~/.kube
( set +x ; while true ; do if kubectl get nodes | tee /dev/stderr | grep -q '\bReady\b' ; then break ; else sleep 5 ; fi ; done )
kubectl get pods --all-namespaces
( set +x ; while ! kubectl get serviceaccount/default ; do sleep 5 ; done )

# Make local-path provisioner on userns remapped docker setup on cgroups v2 work
# -- the pods of the cluster run remapped as well
sudo mkdir -p /var/lib/rancher/k3s/storage
sudo chown $( id -u ) /var/lib/rancher/k3s/storage

( set +x ; for i in $( seq 1 10 ) ; do ip link show cni0 > /dev/null && break ; sleep 3 ; done )
sudo resolvectl dns cni0 $( kubectl get -n kube-system service/kube-dns -o 'jsonpath={.spec.clusterIP}' )
sudo resolvectl domain cni0 cluster.local

kubectl apply -f tests/freeipa-coredns-custom.yaml

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
kubectl exec freeipa-server -- cat /proc/1/uid_map | tee /dev/stderr | grep -q '^ *0 *[1-9]'
PV_DIR=$( kubectl get pvc/freeipa-data-pvc -o 'jsonpath={.spec.volumeName}_{.metadata.namespace}_{.metadata.name}' )
ls -la /var/lib/rancher/k3s/storage/$PV_DIR
IPA_SERVER_HOSTNAME=$( kubectl exec pod/freeipa-server -- hostname -f )
IPA_SERVER_IP=$( kubectl get -o=jsonpath='{.spec.clusterIP}' service freeipa-server-service )
seq 15 -1 0 | while read i ; do dig +short $IPA_SERVER_HOSTNAME | tee /dev/stderr | grep -Fq $IPA_SERVER_IP && break ; sleep 5 ; [ $i == 0 ] && false ; done
seq 15 -1 0 | while read i ; do dig +short -t srv _ldap._tcp.${IPA_SERVER_HOSTNAME#*.} | tee /dev/stderr | grep -Fq "0 100 389 $IPA_SERVER_HOSTNAME." && break ; sleep 5 ; [ $i == 0 ] && false ; done

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
kubectl exec freeipa-replica -- cat /proc/1/uid_map | tee /dev/stderr | grep -q '^ *0 *[1-9]'
PV_DIR=$( kubectl get pvc/freeipa-replica-pvc -o 'jsonpath={.spec.volumeName}_{.metadata.namespace}_{.metadata.name}' )
ls -la /var/lib/rancher/k3s/storage/$PV_DIR
IPA_REPLICA_HOSTNAME=$( kubectl exec pod/freeipa-replica -- hostname -f )
IPA_REPLICA_IP=$( kubectl get -o=jsonpath='{.spec.clusterIP}' service freeipa-replica-service )
dig +short $IPA_REPLICA_HOSTNAME | tee /dev/stderr | grep -Fq $IPA_REPLICA_IP

curl -Lk https://$IPA_REPLICA_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
curl -H "Referer: https://$IPA_REPLICA_HOSTNAME/ipa/ui/" -H 'Accept-Language: fr' -d '{"method":"i18n_messages","params":[[],{}]}' -k https://$IPA_REPLICA_HOSTNAME/ipa/i18n_messages | grep -q utilisateur
echo Secret123 | kubectl exec -i pod/freeipa-replica -- kinit admin

kill $REPLICA_LOGS_PID 2> /dev/null || :
trap - EXIT

echo OK $0.
