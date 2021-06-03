#!/bin/bash

set -e
set -x

curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
( set +x ; while true ; do if kubectl get nodes | tee /dev/stderr | grep -q '\bReady\b' ; then break ; else sleep 5 ; fi ; done )
if [ -n "$2" ] ; then
	sudo k3s ctr images import "$2"
fi
kubectl get pods --all-namespaces
kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-k3s.yaml )
( set +x ; while kubectl get pod/freeipa-server | tee /dev/stderr | grep -Eq '\bPending\b|\bContainerCreating\b' ; do sleep 5 ; done )
if ! kubectl get pod/freeipa-server | grep -q '\bRunning\b' ; then
	kubectl describe pod/freeipa-server
	kubectl logs pod/freeipa-server
	exit 1
fi
kubectl logs -f pod/freeipa-server &
trap "kill $! 2> /dev/null || : ; trap - EXIT" EXIT
( set +x ; while true ; do if kubectl get pod/freeipa-server | grep -q '\b1/1\b' ; then kill $! ; break ; else sleep 5 ; fi ; done )
kubectl describe pod/freeipa-server
ls -la /var/lib/rancher/k3s/storage/pvc-*
IPA_SERVER_HOSTNAME=$( kubectl get -o=jsonpath='{.spec.containers[0].env[?(@.name=="IPA_SERVER_HOSTNAME")].value}' pod freeipa-server )
# echo $( kubectl get -o=jsonpath='{.spec.clusterIP}' service freeipa-server-service ) $IPA_SERVER_HOSTNAME >> /etc/hosts
if ! test -f /etc/resolv.conf.backup ; then
	sudo mv /etc/resolv.conf /etc/resolv.conf.backup
fi
sudo systemctl stop systemd-resolved.service || :
echo nameserver $( kubectl get -o=jsonpath='{.spec.clusterIP}' service freeipa-server-service ) | sudo tee /etc/resolv.conf
curl -Lk https://$IPA_SERVER_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
echo Secret123 | kubectl exec -i pod/freeipa-server -- kinit admin
