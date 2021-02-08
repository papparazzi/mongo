#!/bin/bash

cp /stuff/mongodb.pem /secret/mongodb.pem
cp /stuff/keyfile/keyfile /secret/keyfile && chmod 600 /secret/keyfile

function mongo_cmd() {
  mongo --authenticationDatabase admin --sslAllowInvalidCertificates --ssl --sslPEMKeyFile ${SSL_PEM_FILE}  $@;
}

# replset_addr return the address of the current replSet
function replset_addr() {
  local current_endpoints db
  db="${1:-}"
  current_endpoints="$(endpoints)"
  if [ -z "${current_endpoints}" ]; then
    echo "Cannot get address of replica set: no nodes are listed in service!"
    echo "CAUSE: DNS lookup for '${MONGODB_SERVICE_NAME:-mongodb}' returned no results."
    return 1
  fi
  echo "mongodb://${current_endpoints//[[:space:]]/,}/${db}?replicaSet=${MONGODB_REPLICA_NAME}"
}

function endpoints() {
  service_name=${MONGODB_SERVICE_NAME:-mongodb}
  dig ${service_name} A +search +short 2>/dev/null
}

function _wait_for_mongo() {
  local operation=${1:-1}
  local message="up"
  if [[ ${operation} -eq 0 ]]; then
    message="down"
  fi

  local i
  for i in $(seq 20); do
    echo "=> ${2:-} Waiting for MongoDB daemon ${message}"
    if ([[ ${operation} -eq 1 ]] && mongo_cmd <<<"quit()") || ([[ ${operation} -eq 0 ]] && ! mongo_cmd <<<"quit()"); then
      echo "=> MongoDB daemon is ${message}"
      return 0
    fi
    sleep 2
  done
  echo "=> Giving up: MongoDB daemon is not ${message}!"
  return 1
}

function initiate() {
  local host="$1"

  local config="{_id: '${MONGODB_REPLICA_NAME}', members: [{_id: 0, host: '${host}'}]}"

  echo "Initiating MongoDB replica using: ${config}"
  mongo_cmd --host localhost --quiet <<<"quit(rs.initiate(${config}).ok ? 0 : 1)"

  echo "Waiting for PRIMARY status ..."
  mongo_cmd --host localhost --quiet <<<"while (!rs.isMaster().ismaster) { sleep(100); }"

  echo "Successfully initialized replica set"
}

function add_member() {
  local host="$1"
  echo "Adding ${host} to replica set ..."

  if ! mongo_cmd "$(replset_addr admin)" -u admin -p"${MONGODB_ADMIN_PASSWORD}" --quiet <<<"while (!rs.add('${host}').ok) { sleep(100); }"; then
    echo "ERROR: couldn't add host to replica set!"
    return 1
  fi

  echo "Waiting for PRIMARY/SECONDARY status ..."
  mongo_cmd --host localhost --quiet <<<"while (!rs.isMaster().ismaster && !rs.isMaster().secondary) { sleep(100); }"

  echo "Successfully joined replica set"
  >/tmp/initialized
}

function mongo_create_admin() {
  if [[ -z "${MONGODB_ADMIN_PASSWORD:-}" ]]; then
    echo >&2 "=> MONGODB_ADMIN_PASSWORD is not set. Authentication can not be set up."
    exit 1
  fi

  # Set admin password
  local js_command="db.createUser({user: 'admin', pwd: '${MONGODB_ADMIN_PASSWORD}', roles: ['root']});"
  if ! mongo ${2:-"localhost"}/admin ${1:-} --sslAllowInvalidCertificates --ssl --sslPEMKeyFile ${SSL_PEM_FILE} --eval "${js_command}"; then
    echo >&2 "=> Failed to create MongoDB admin user."
    exit 1
  fi
  
  echo "Successfully setup Admin user."
  sleep 20
  >/tmp/initialized
}

echo "Running Mongo"
/usr/bin/mongod \
	--port 27017 \
	--bind_ip 0.0.0.0 \
	--smallfiles \
    --noprealloc \
	--keyFile ${MONGODB_KEYFILE} \
	--replSet ${MONGODB_REPLICA_NAME} \
	--dbpath /var/lib/mongodb/data \
	--timeStampFormat iso8601-utc \
	--sslMode requireSSL \
	--sslPEMKeyFile ${SSL_PEM_FILE} \
    --sslAllowConnectionsWithoutCertificates \
	--sslAllowInvalidHostnames &

echo "Waiting for local MongoDB to accept connections  ..."
sleep 5
_wait_for_mongo 1

if [[ $(mongo_cmd --quiet <<<'db.isMaster().setName' | tail -n 1) == "${MONGODB_REPLICA_NAME}" ]]; then
  echo "Replica set '${MONGODB_REPLICA_NAME}' already exists, skipping initialization"
  >/tmp/initialized
  while(true); do
    sleep 5
  done 
fi


export MEMBER_ID="${HOSTNAME##*-}"
export MEMBER_HOST="$(hostname -f)"

# Initialize replica set only if we're the first member
if [ "${MEMBER_ID}" = '0' ]; then
  initiate "${MEMBER_HOST}" 
  mongo_create_admin
else
  add_member "${MEMBER_HOST}"
fi

while true
do
	sleep 1
done