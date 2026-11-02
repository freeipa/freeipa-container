#!/bin/bash

set -euo pipefail
set -x

kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-k8s.yaml )
( for i in $( seq 60 ) ; do ! kubectl get pod/freeipa-server | tee /dev/stderr | grep -E '\bPending\b|\bContainerCreating\b' > /dev/null && exit ; set +x ; echo --- ; sleep 5 ; done ; false )
if ! kubectl get pod/freeipa-server | grep '\bRunning\b' > /dev/null ; then
	kubectl describe pod/freeipa-server
	kubectl logs pod/freeipa-server
	exit 1
fi
( for i in $( seq 10 ) ; do kubectl logs pod/freeipa-server > /dev/null && exit ; set +x ; sleep 5 ; done ; false )
kubectl logs -f pod/freeipa-server &
MASTER_LOGS_PID=$!
trap "kill $MASTER_LOGS_PID 2> /dev/null || : ; trap - EXIT" EXIT
( set +x ; for i in $( seq 300 ) ; do kubectl get pod/freeipa-server | grep -E 'Error|\b1/1\b' > /dev/null && exit ; sleep 5 ; done ; false )
kill $MASTER_LOGS_PID || :
kubectl describe pod/freeipa-server
kubectl exec freeipa-server -- cat /proc/1/uid_map | tee /dev/stderr | grep '^ *0 *[1-9]' > /dev/null
if ! kubectl exec pod/freeipa-server -- systemctl is-system-running ; then
	kubectl exec pod/freeipa-server -- systemctl
	kubectl exec pod/freeipa-server -- systemctl status
	exit 1
fi

LOCAL_PATH_NS=
for ns in local-path-storage kube-system ; do
	if kubectl get -n $ns configmap/local-path-config ; then LOCAL_PATH_NS=$ns ; fi
done
LOCAL_PATH_DIR=$( kubectl get -n $LOCAL_PATH_NS configmap/local-path-config -o jsonpath="{.data['config\.json']}" \
	| jq -r '.nodePathMap[] | select(.node == "DEFAULT_PATH_FOR_NON_LISTED_NODES").paths[0]' )
PV_DIR=$( kubectl get pvc/freeipa-data-pvc -o 'jsonpath={.spec.volumeName}_{.metadata.namespace}_{.metadata.name}' )
ls -la $LOCAL_PATH_DIR/$PV_DIR
IPA_SERVER_HOSTNAME=$( kubectl exec pod/freeipa-server -- hostname -f )
IPA_SERVER_IP=$( kubectl get -o=jsonpath='{.spec.clusterIP}' service freeipa-server-service )

( for i in $( seq 60 ) ; do dig +short $IPA_SERVER_HOSTNAME | tee /dev/stderr | grep -F $IPA_SERVER_IP > /dev/null && exit ; set +x ; sleep 5 ; done ; false )
( for i in $( seq 60 ) ; do dig +short -t srv _ldap._tcp.${IPA_SERVER_HOSTNAME#*.} | tee /dev/stderr | grep -F "0 100 389 $IPA_SERVER_HOSTNAME." > /dev/null && exit ; set +x ; sleep 5 ; done ; false )

curl -sSLk --fail-with-body https://$IPA_SERVER_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
curl -sSk --fail-with-body -H "Referer: https://$IPA_SERVER_HOSTNAME/ipa/ui/" -H 'Accept-Language: fr' -d '{"method":"i18n_messages","params":[[],{}]}' https://$IPA_SERVER_HOSTNAME/ipa/i18n_messages | grep utilisateur > /dev/null
echo Secret123 | kubectl exec -i pod/freeipa-server -- kinit admin
kubectl exec -i pod/freeipa-server -- ipa user-add --first Bob --last Nowak bob$$

kubectl exec -i pod/freeipa-server -- ipa host-del client1.dom1.default.svc.cluster.local || :
kubectl exec -i pod/freeipa-server -- ipa host-add --password=Secret124 --force client1.dom1.default.svc.cluster.local

if ! podman images localhost/ipa-client | grep '^localhost/ipa-client' ; then
        podman build -t localhost/ipa-client -f Dockerfile.test-client .
fi
podman run -d -t --name ipa-client -h client1.dom1.default.svc.cluster.local localhost/ipa-client
if ! ( for i in $( seq 10 ) ; do podman exec ipa-client systemctl is-system-running | grep -F running && exit ; set +x ; sleep 1 ; done ; false ) ; then
	podman logs ipa-client
	exit 1
fi
podman exec ipa-client ipa-client-install -U --password=Secret124 --no-ntp
podman exec ipa-client id bob$$

podman rm -f ipa-client

kubectl exec -i pod/freeipa-server -- ipa host-del client1.dom1.default.svc.cluster.local

kill $MASTER_LOGS_PID 2> /dev/null || :
trap - EXIT

kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-replica-k8s.yaml )
( for i in $( seq 60 ) ; do ! kubectl get pod/freeipa-replica | tee /dev/stderr | grep -E '\bPending\b|\bContainerCreating\b' > /dev/null && exit ; set +x ; echo --- ; sleep 5 ; done ; false )
if ! kubectl get pod/freeipa-replica | grep '\bRunning\b' > /dev/null ; then
	kubectl describe pod/freeipa-replica
	kubectl logs pod/freeipa-replica
	exit 1
fi
( for i in $( seq 10 ) ; do kubectl logs pod/freeipa-replica > /dev/null && exit ; set +x ; sleep 5 ; done ; false )
kubectl logs -f pod/freeipa-replica &
REPLICA_LOGS_PID=$!
trap "kill $REPLICA_LOGS_PID 2> /dev/null || : ; trap - EXIT" EXIT
( set +x ; for i in $( seq 300 ) ; do kubectl get pod/freeipa-replica | grep -E 'Error|\b1/1\b' > /dev/null && exit ; sleep 5 ; done ; false )
kill $REPLICA_LOGS_PID || :
kubectl describe pod/freeipa-replica
kubectl exec freeipa-replica -- cat /proc/1/uid_map | tee /dev/stderr | grep '^ *0 *[1-9]' > /dev/null
if ! kubectl exec pod/freeipa-replica -- systemctl is-system-running ; then
	kubectl exec pod/freeipa-replica -- systemctl
	kubectl exec pod/freeipa-replica -- systemctl status
	exit 1
fi

PV_DIR=$( kubectl get pvc/freeipa-replica-pvc -o 'jsonpath={.spec.volumeName}_{.metadata.namespace}_{.metadata.name}' )
ls -la $LOCAL_PATH_DIR/$PV_DIR
IPA_REPLICA_HOSTNAME=$( kubectl exec pod/freeipa-replica -- hostname -f )
IPA_REPLICA_IP=$( kubectl get -o=jsonpath='{.spec.clusterIP}' service freeipa-replica-service )
dig +short $IPA_REPLICA_HOSTNAME | tee /dev/stderr | grep -F $IPA_REPLICA_IP > /dev/null

curl -sSLk --fail-with-body https://$IPA_REPLICA_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
curl -sSk --fail-with-body -H "Referer: https://$IPA_REPLICA_HOSTNAME/ipa/ui/" -H 'Accept-Language: fr' -d '{"method":"i18n_messages","params":[[],{}]}' https://$IPA_REPLICA_HOSTNAME/ipa/i18n_messages | grep utilisateur > /dev/null
echo Secret123 | kubectl exec -i pod/freeipa-replica -- kinit admin

kubectl exec -i pod/freeipa-server -- ipa host-add --password=Secret124 --force client1.dom1.default.svc.cluster.local

podman run -d -t --name ipa-client -h client1.dom1.default.svc.cluster.local localhost/ipa-client
if ! ( for i in $( seq 10 ) ; do podman exec ipa-client systemctl is-system-running | grep -F running && exit ; set +x ; sleep 1 ; done ; false ) ; then
	podman logs ipa-client
	exit 1
fi
podman exec ipa-client ipa-client-install -U --domain=dom1.default.svc.cluster.local --server=freeipa-replica.dom1.default.svc.cluster.local --password=Secret124 --no-ntp
podman exec ipa-client id bob$$

podman rm -f ipa-client

kill $REPLICA_LOGS_PID 2> /dev/null || :
trap - EXIT

echo OK $0.
