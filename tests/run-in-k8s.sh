#!/bin/bash

set -euo pipefail
set -x

kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-k8s.yaml )
( set +x ; while kubectl get pod/freeipa-server | tee /dev/stderr | grep -E '\bPending\b|\bContainerCreating\b' > /dev/null ; do sleep 5 ; done )
if ! kubectl get pod/freeipa-server | grep '\bRunning\b' > /dev/null ; then
	kubectl describe pod/freeipa-server
	kubectl logs pod/freeipa-server
	exit 1
fi
( set +x ; for i in $( seq 1 10 ) ; do kubectl logs pod/freeipa-server > /dev/null && break ; sleep 3 ; done )
kubectl logs -f pod/freeipa-server &
MASTER_LOGS_PID=$!
trap "kill $MASTER_LOGS_PID 2> /dev/null || : ; trap - EXIT" EXIT
( set +x ; while true ; do if kubectl get pod/freeipa-server | grep -E 'Error|\b1/1\b' > /dev/null ; then kill $MASTER_LOGS_PID ; break ; else sleep 5 ; fi ; done )
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
seq 60 -1 0 | while read i ; do dig +short $IPA_SERVER_HOSTNAME | tee /dev/stderr | grep -F $IPA_SERVER_IP > /dev/null && break ; sleep 5 ; [ $i == 0 ] && false ; done
seq 60 -1 0 | while read i ; do dig +short -t srv _ldap._tcp.${IPA_SERVER_HOSTNAME#*.} | tee /dev/stderr | grep -F "0 100 389 $IPA_SERVER_HOSTNAME." > /dev/null && break ; sleep 5 ; [ $i == 0 ] && false ; done

curl -Lk https://$IPA_SERVER_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
curl -H "Referer: https://$IPA_SERVER_HOSTNAME/ipa/ui/" -H 'Accept-Language: fr' -d '{"method":"i18n_messages","params":[[],{}]}' -k https://$IPA_SERVER_HOSTNAME/ipa/i18n_messages | grep utilisateur > /dev/null
echo Secret123 | kubectl exec -i pod/freeipa-server -- kinit admin

kill $MASTER_LOGS_PID 2> /dev/null || :
trap - EXIT

kubectl create -f <( sed "s#image:.*#image: $1#" tests/freeipa-replica-k8s.yaml )
( set +x ; while kubectl get pod/freeipa-replica | tee /dev/stderr | grep -E '\bPending\b|\bContainerCreating\b' > /dev/null ; do sleep 5 ; done )
if ! kubectl get pod/freeipa-replica | grep '\bRunning\b' > /dev/null ; then
	kubectl describe pod/freeipa-replica
	kubectl logs pod/freeipa-replica
	exit 1
fi
( set +x ; for i in $( seq 1 10 ) ; do kubectl logs pod/freeipa-replica > /dev/null && break ; sleep 3 ; done )
kubectl logs -f pod/freeipa-replica &
REPLICA_LOGS_PID=$!
trap "kill $REPLICA_LOGS_PID 2> /dev/null || : ; trap - EXIT" EXIT
( set +x ; while true ; do if kubectl get pod/freeipa-replica | grep -E 'Error|\b1/1\b' > /dev/null ; then kill $REPLICA_LOGS_PID ; break ; else sleep 5 ; fi ; done )
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

curl -Lk https://$IPA_REPLICA_HOSTNAME/ | grep -E 'IPA: Identity Policy Audit|Identity Management'
curl -H "Referer: https://$IPA_REPLICA_HOSTNAME/ipa/ui/" -H 'Accept-Language: fr' -d '{"method":"i18n_messages","params":[[],{}]}' -k https://$IPA_REPLICA_HOSTNAME/ipa/i18n_messages | grep utilisateur > /dev/null
echo Secret123 | kubectl exec -i pod/freeipa-replica -- kinit admin

kill $REPLICA_LOGS_PID 2> /dev/null || :
trap - EXIT

echo OK $0.
