#!/bin/bash

qd=/qdata
mkdir -p $qd/{logs,constellation/keys}
mkdir -p $qd/dd/{geth,keystore}

echo -n '_NODEKEY_' > $qd/dd/geth/nodekey

