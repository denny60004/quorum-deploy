#!/bin/bash

rm -rf qdata_[0-9] qdata_[0-9][0-9]
rm -f docker-compose.yml
rm -f consortium.yaml
rm -f quorum_config.yaml
rm -f crux_config.yaml
rm -f backend_config.yaml
rm -f node_secret.yaml
rm -rf scripts

# Shouldn't be needed, but just in case:
rm -f static-nodes.json genesis.json
