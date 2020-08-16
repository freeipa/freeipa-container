#!/bin/bash

set -e
set -x

curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
while true ; do if kubectl get nodes | tee /dev/stderr | grep -q '\bReady\b' ; then break ; else sleep 5 ; fi ; done
if [ -n "$2" ] ; then
	sudo k3s ctr images import "$2"
fi
kubectl get pods --all-namespaces
kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-k3s.yaml )
while true ; do if kubectl get pod/freeipa-server | tee /dev/stderr | grep -q '\bRunning\b' ; then break ; else sleep 5 ; fi ; done
kubectl logs -f pod/freeipa-server &
( set -x ; while true ; do if kubectl get pod/freeipa-server | grep -q '\b1/1\b' ; then kill $! ; break ; else sleep 5 ; fi ; done )
kubectl describe pod/freeipa-server
ls -la /var/lib/rancher/k3s/storage/pvc-*
