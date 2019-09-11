#!/bin/bash

#### Configuration options #############################################
. ip.cfg

image=denny60004/quorum-crux:latest
GETH='/usr/local/bin/geth'
BOOTNODE='/usr/local/bin/bootnode'
CONSTELLATION='/usr/local/bin/crux'

########################################################################

nnodes=${#ips[@]}

if [[ $nnodes < 2 ]]
then
    echo "ERROR: There must be more than one node IP address."
    exit 1
fi

./cleanup.sh

uid=`id -u`
gid=`id -g`
pwd=`pwd`

#### Create directories for each node's configuration ##################
echo '[1] ~~~> Configuring for '$nnodes' nodes.'

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    mkdir -p $qd/{logs,constellation/keys}
    mkdir -p $qd/dd/geth

    let n++
done


#### Make static-nodes.json and store keys #############################
echo
echo '[2] ~~~> Creating Enodes and static-nodes.json.'

echo "[" > static-nodes.json
n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    nodekey_file='/qdata/dd/geth/nodekey'

    # Generate the node's Enode and key
    enode=`docker run \
      -u $uid:$gid \
      -v $pwd/$qd:/qdata \
      --rm \
      $image \
      /bin/bash -c "$BOOTNODE -genkey $nodekey_file; \
      $BOOTNODE -nodekey $nodekey_file -writeaddress"`

    # Add the enode to static-nodes.json
    enode_url='enode://'$enode'@'$ip':30303?discport=0&raftport=23000'
    sep=`[[ $n < $nnodes ]] && echo ","`
    echo ' "'$enode_url'"'$sep >> static-nodes.json

    let n++
done
echo "]" >> static-nodes.json


#### Create accounts, keys and genesis.json file #######################
echo
echo '[3] ~~~> Creating Ether accounts and genesis.json.'

cat > genesis.json <<EOF
{
  "alloc": {
EOF

n=1
for ip in ${ips[*]}
do
  qd=qdata_$n

  # Generate an Ether account for the node
  touch $qd/passwords.txt
  account=`docker run \
    -u $uid:$gid \
    -v $pwd/$qd:/qdata \
    --rm \
    $image \
    $GETH \
    --datadir=/qdata/dd \
    --password /qdata/passwords.txt \
    account new | cut -c 11-50`

  # Add the account to the genesis block so it has some Ether at start-up
  sep=`[[ $n < $nnodes ]] && echo ","`
  cat >> genesis.json <<EOF
    "${account}": {
      "balance": "1000000000000000000000000000"
    }${sep}
EOF

  let n++
done

cat >> genesis.json <<EOF
  },
  "coinbase": "0x0000000000000000000000000000000000000000",
  "config": {
    "homesteadBlock": 0,
    "chainId": 10,
    "eip155Block": null,
    "eip158Block": null,
    "isQuorum": true
  },
  "difficulty": "0x0",
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "gasLimit": "0xE0000000",
  "mixhash": "0x00000000000000000000000000000000000000647572616c65787365646c6578",
  "nonce": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "timestamp": "0x00"
}
EOF


#### Make node list for tm.conf ########################################

nodelist=
n=1
for ip in ${ips[*]}
do
    sep=`[[ $ip != ${ips[0]} ]] && echo ","`
    nodelist=${nodelist}${sep}"http://${ip}:9000/"
    let n++
done


#### Complete each node's configuration ################################
echo
echo '[4] ~~~> Creating Quorum keys and finishing configuration.'

n=1
for ip in ${ips[*]}
do
  qd=qdata_$n

  cat templates/tm.conf \
    | sed s/_NODEIP_/${ips[$((n-1))]}/g \
    | sed s%_NODELIST_%$nodelist%g \
    > $qd/tm.conf

  cp genesis.json $qd/genesis.json
  cp static-nodes.json $qd/dd/static-nodes.json

  # Generate Quorum-related keys (used by Constellation)
  docker run \
    -u $uid:$gid \
    -v $pwd/$qd:/qdata \
    --rm \
    --workdir=/qdata/constellation/keys \
    $image \
    $CONSTELLATION \
    --generate-keys=tm
  echo 'Node '$n' public key: '`cat $qd/constellation/keys/tm.pub`

  cp templates/start.sh $qd/start.sh
  chmod 755 $qd/start.sh

  let n++
done
rm -rf genesis.json static-nodes.json


#### Create the docker-compose file ####################################
echo
echo '[5] ~~~> Creating docker-compose file.'

cat > docker-compose.yml <<EOF
version: '3'
services:
EOF

n=1
for ip in ${ips[*]}
do
  qd=qdata_$n

  cat >> docker-compose.yml <<EOF
  node_$n:
    image: $quorum_image
    volumes:
      - './$qd:/qdata'
    networks:
      quorum_net:
        ipv4_address: '$ip'
    ports:
      - $((n+22000)):8545
    user: '$uid:$gid'
    command: bash /qdata/start.sh
EOF

  let n++
done

cat >> docker-compose.yml <<EOF
  explorer_backend:
    image: $explorer_backend_image
    ports:
      - 8081:8081
    environment:
      - JAVA_OPTS=
      - EXPLORER_PORT=8081
      - NODE_ENDPOINT=http://${ips[1]}:8545
      - MONGO_CLIENT_URI=mongodb://docker.for.mac.host.internal:27017
      - MONGO_DB_NAME=consortium-explorer
      - UI_IP=http://localhost:5000
    networks:
      - quorum_net
    depends_on:
      - explorer_mongodb
  explorer_mongodb:
    image: $explorer_mongo_image
    ports:
      - 27017:27017
    entrypoint: mongod --smallfiles --logpath=/dev/null --bind_ip "0.0.0.0"
    depends_on:
      - node_1
      - node_2
      - node_3
  explorer_ui:
    image: $explorer_ui_image
    ports:
      - 5000:5000
    environment:
      - REACT_APP_EXPLORER=http://localhost:8081
EOF

cat >> docker-compose.yml <<EOF

networks:
  quorum_net:
    driver: bridge
    ipam:
      driver: default
      config:
      - subnet: $subnet
EOF

#### Create pre-populated contracts ####################################
echo
echo '[6] ~~~> Generating sample contract scripts.'

mkdir scripts

# Private contract - insert Node 2 as the recipient
cat templates/contract_pri.js \
  | sed s:_NODEKEY_:`cat qdata_2/constellation/keys/tm.pub`:g \
  > scripts/contract_pri.js

# Public contract - no change required
cp templates/contract_pub.js scripts/
cp templates/contract_act.js scripts/

### Setup init script ################################################
./geninit.sh

#### Create the k8s yaml file ####################################
echo
echo '[7] ~~~> Creating kubernetes definition yaml.'

n=1
port=31701
for ip in ${ips[*]}
do
  qd=qdata_$n

  pad='          '
  cat $qd/init.sh \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > init.sh
  echo "$pad""bash /qdata/start.sh" >> init.sh

  pad='    '
  cat $qd/tm.conf \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > tm.conf
  cat templates/crux_config.yaml \
    | sed "s;_NODE_ID_;$n;g" \
    | sed '/_CRUX_/r tm.conf' \
    | sed '/_CRUX_/d' \
    >> crux_config.yaml
  cat $qd/constellation/keys/tm.pub \
    | base64 \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > tm.pub
  cat $qd/constellation/keys/tm.key \
    | base64 \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > tm.key
  account=`ls $qd/dd/keystore | head -n 1`
  cat $qd/dd/keystore/$account \
    | base64 \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > account.key
  cat $qd/passwords.txt \
    | base64 \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > passwords.txt
  cat templates/node_secret.yaml \
    | sed "s;_NODE_ID_;$n;g" \
    | sed '/_TM_PUB_/r tm.pub' \
    | sed '/_TM_PUB_/d' \
    | sed '/_TM_KEY_/r tm.key' \
    | sed '/_TM_KEY_/d' \
    | sed '/_ACCOUNT_KEY_/r account.key' \
    | sed '/_ACCOUNT_KEY_/d' \
    | sed '/_PASSWORD_/r password.txt' \
    | sed '/_PASSWORD_/d' \
    >> node_secret.yaml

  cat templates/consortium.yaml \
    | sed "s;_NODE_ID_;$n;g" \
    | sed "s;_NODE_IP_;$ip;g" \
    | sed "s;_NODE_PORT_;$port;g" \
    | sed "s;_QUORUM_IMAGE_;$quorum_image;g" \
    | sed "s;_IMAGE_PULL_POLICY_;$image_pull_policy;g" \
    | sed '/_NODE_SCRIPT_/r init.sh' \
    | sed '/_NODE_SCRIPT_/d' \
    >> consortium.yaml

  rm init.sh tm.conf tm.pub tm.key account.key passwords.txt
  let n++
  let port++
done

# create config map
pad='    '
cat $qd/dd/static-nodes.json \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > static-nodes.json
cat $qd/genesis.json \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > genesis.json
cat $qd/start.sh \
    | sed "s/^/$pad/" \
    | sed '/^[[:space:]]*$/d' \
    > start_node.sh

cat templates/quorum_config.yaml \
  | sed '/_STATIC_NODES_/r static-nodes.json' \
  | sed '/_STATIC_NODES_/d' \
  | sed '/_GENESIS_/r genesis.json' \
  | sed '/_GENESIS_/d' \
  | sed '/_START_/r start_node.sh' \
  | sed '/_START_/d' \
  >> quorum_config.yaml

rm static-nodes.json genesis.json start_node.sh

cat >> consortium.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  annotations:
    app: consortiumchain
    version: '1'
  creationTimestamp: null
  labels:
    name: node-endpoint
  name: node-endpoint
spec:
  type: LoadBalancer
  clusterIP: $node_endpoint_ip
  ports:
  - name: rpc
    port: 8545
    targetPort: 8545
  selector:
    app: consortiumchain
status:
  loadBalancer: {}
EOF

