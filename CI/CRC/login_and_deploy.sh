#!/bin/bash
SCRIPT_PATH=./krkn/CI/CRC
DEPLOYMENT_PATH=$SCRIPT_PATH/deployment.yaml
CLUSTER_INFO=cluster_infos.json
CLUSTER_INFO_PATH=./workdir/crc/$CLUSTER_INFO

[[ ! -d ./krkn ]] && echo "[ERROR] please run $0 from GitHub action root directory" && exit 1
[[ -z $KUBEADMIN_PWD ]] && echo "[ERROR] kubeadmin password not set, please check the repository secrets" && exit 1
[[ -z $DEPLOYMENT_NAME ]] && echo "[ERROR] please set \$DEPLOYMENT_NAME environment variable" && exit 1
[[ -z $NAMESPACE ]] && echo "[ERROR] please set \$NAMESPACE environment variable" && exit 1
[[ ! -f $CLUSTER_INFO_PATH ]] && echo  "[ERROR] cluster_info.json not found in $CLUSTER_INFO_PATH" && exit 1 

OPENSSL=`which openssl 2>/dev/null`
[[ $? != 0 ]] && echo "[ERROR]: openssl missing, please install it and try again" && exit 1
OC=`which oc 2>/dev/null`
[[ $? != 0 ]] && echo "[ERROR]: oc missing, please install it and try again" && exit 1
SED=`which sed 2>/dev/null`
[[ $? != 0 ]] && echo "[ERROR]: sed missing, please install it and try again" && exit 1
JQ=`which jq 2>/dev/null`
[[ $? != 0 ]] && echo "[ERROR]: jq missing, please install it and try again" && exit 1
ENVSUBST=`which envsubst 2>/dev/null`
[[ $? != 0 ]] && echo "[ERROR]: envsubst missing, please install it and try again" && exit 1

API_ADDRESS="$($JQ -r '.api.address' $CLUSTER_INFO_PATH)"
API_PORT="$($JQ -r '.api.port' $CLUSTER_INFO_PATH)"
BASE_HOST=`$JQ -r '.api.address'  $CLUSTER_INFO_PATH | sed -r 's#https:\/\/api\.(.+\.nip\.io)#\1#'`
FQN=$DEPLOYMENT_NAME.apps.$BASE_HOST

echo "deployment_fqn=$FQN" >> $GITHUB_ENV
echo "api_address=$API_ADDRESS" >> $GITHUB_ENV
echo "api_port=$API_PORT" 
echo "[INFO] deployment fully qualified name will be available in \${{ env.deployment_fqn }} with value $FQN"
echo "[INFO] OCP API address will be available in \${{ env.api_address }} with value $API_ADDRESS"
echo "[INFO] OCP API port fully qualified name will be available in \${{ env.api_port }} with value $API_PORT"

echo "[INFO] logging in on $API_ADDRESS"
$OC login  --insecure-skip-tls-verify -u kubeadmin -p $KUBEADMIN_PWD $API_ADDRESS:$API_PORT > /dev/null 2>&1
echo "[INFO] deploying example deployment: $DEPLOYMENT_NAME in namespace: $NAMESPACE"
$ENVSUBST < $DEPLOYMENT_PATH | $OC apply -f - > /dev/null 2>&1


# setting deployment fqn on github env


echo "[INFO] creating SSL self-signed certificates for route https://$FQN"
$OPENSSL genrsa -out servercakey.pem > /dev/null 2>&1
$OPENSSL req -new -x509 -key servercakey.pem -out serverca.crt -subj "/CN=$FQN/O=Red Hat Inc./C=US" > /dev/null 2>&1
$OPENSSL genrsa -out server.key > /dev/null 2>&1
$OPENSSL req -new -key server.key -out server_reqout.txt -subj "/CN=$FQN/O=Red Hat Inc./C=US" > /dev/null 2>&1
$OPENSSL x509 -req -in server_reqout.txt -days 3650 -sha256 -CAcreateserial -CA serverca.crt -CAkey servercakey.pem -out server.crt > /dev/null 2>&1
echo "[INFO] creating deployment: $DEPLOYMENT_NAME public route: https://$FQN"
$OC create route --namespace $NAMESPACE  edge --service=$DEPLOYMENT_NAME-service --cert=server.crt --key=server.key --ca-cert=serverca.crt --hostname="$FQN" > /dev/null 2>&1
