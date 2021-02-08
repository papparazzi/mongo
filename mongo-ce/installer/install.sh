#!/bin/bash

while getopts d:c:k:a: option
do
 case "${option}"
 in
 d) DEPLOY=${OPTARG};;
 c) CLEAN=${OPTARG};;
 k) KEYFILE_SECRET=${OPTARG};;
 a) ADMIN_PASSWORD=${OPTARG};;
 esac
done

# Make sure current directory is on the PATH
PATH=$PATH:.

#Ensure kubectl and oc are installed
if [ ! -e "./oc" ]; then
  echo "Installing oc and kubectl clients"
  # Get OC client
  if [[ "$OSTYPE" == darwin* ]]; then
    wget https://github.com/openshift/origin/releases/download/v3.11.0/openshift-origin-client-tools-v3.11.0-0cbc58b-mac.zip -O openshift-origin-client-tools-v3.11.0-0cbc58b-mac.zip
    unzip ./openshift-origin-client-tools-v3.11.0-0cbc58b-mac.zip -d openshift-origin-client-tools-v3.11.0-0cbc58b-mac
    rm ./openshift-origin-client-tools-v3.11.0-0cbc58b-mac.zip
    mv ./openshift-origin-client-tools-v3.11.0-0cbc58b-mac/oc .
    mv ./openshift-origin-client-tools-v3.11.0-0cbc58b-mac/kubectl .
    rm -rf ./openshift-origin-client-tools-v3.11.0-0cbc58b-mac
  else
    wget https://github.com/openshift/origin/releases/download/v3.11.0/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz -O openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
    tar -xvf ./openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
    rm ./openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
    mv ./openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/oc .
    mv ./openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/kubectl .
    rm -rf ./openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit
  fi
fi

#Ensure envsubst is installed
if [ ! -e "./envsubst" ]; then
  wget https://github.com/a8m/envsubst/releases/download/v1.1.0/envsubst-`uname -s`-`uname -m` -O envsubst
  chmod +x envsubst
fi 

PATH="./:$PATH"

# verify that cluster session exists
oc whoami >/dev/null 2>&1 || { echo "Not logged in to OpenShift cluster, you must login (oc login) before running this script."; exit 1; }

# verify that image registry route was created
REGISTRY_ROUTE=$(oc get routes -n openshift-image-registry -o jsonpath='{.items[0].spec.host}' 2>/dev/null) || { echo "a route to the internal image registry must be created before running this script"; exit $?; }
REGISTRY_PULL_PREFIX=image-registry.openshift-image-registry.svc:5000

if ${CLEAN:-false} == "true"; then
  # Clean up if needed
  oc project mongo
  oc delete statefulset mongo
  oc delete service mongo
  oc delete secret docker-secret
  oc delete secret mongo-ca
  oc delete secret mongo-keyfile-secret
  oc delete pvc mongo-persistent-storage-mongo-0 mongo-persistent-storage-mongo-1 mongo-persistent-storage-mongo-2
  oc delete project mongo
  exit 0
fi

: ${KEYFILE_SECRET?"Please set a keyfile secret for mongo e.g iamsecret"}
: ${ADMIN_PASSWORD?"Please set a admin secret for accessing Mongo, this can be changed later"}

export KEYFILE_SECRET=$(echo "$KEYFILE_SECRET" | base64)
export ADMIN_PASSWORD="$ADMIN_PASSWORD"
export DOCKER_IMAGE="$REGISTRY_PULL_PREFIX/mongo/mongo-ce:latest"

PROJECT_EXISTS=$(oc get projects | grep -w mongo | wc -l | tr -d '[:space:]')
if [ ${PROJECT_EXISTS} == 1 ]; then
  oc project mongo
else
  oc new-project mongo
  oc config set-context $(oc config current-context) --namespace=mongo
fi

# Grab the docker pull secret from the namespace
INTERNAL_REG_SECRET=$(oc get sa default -o jsonpath='{.imagePullSecrets[*].name}')
export REGISTRY_SECRET=$(oc get secret $INTERNAL_REG_SECRET -o jsonpath='{.data.\.dockercfg}') || { echo "could not retrieve the pull secret from the internal image registry, exiting"; exit $?; }

# Tag and push the docker image
docker login -u $(oc whoami) -p $(oc whoami -t) $REGISTRY_ROUTE || { echo "could not login to the internal image registry with docker, verify that the user has access"; exit $?; }
docker tag mongo-ce $REGISTRY_ROUTE/mongo/mongo-ce:latest
docker push $REGISTRY_ROUTE/mongo/mongo-ce:latest || { echo "failed to push the mongo-ce image to the internal image registry"; exit $?; }

#Setup statefulset by replacing variables
envsubst < ../statefulset-template.yaml > ../statefulset.yaml
if ${DEPLOY:-false} == "true"; then
  oc create secret generic mongo-ca --from-file=../certificate/mongodb.pem
  oc patch serviceaccount/default --type='json' -p='[{"op":"add","path":"/imagePullSecrets/-","value":{"name":"docker-secret"}}]'
  oc apply -f ../statefulset.yaml
  #Cleanup
  rm -rf ../statefulset.yaml
fi

# Expose the mongo service for (dev/test)
oc create route passthrough --service mongo --port 27017

