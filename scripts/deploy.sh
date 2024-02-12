#!/usr/bin/env bash
# Copyright (C) 2024, Ava Labs, Inc. All rights reserved.
# See the file LICENSE for licensing terms.

set -e

REPO_BASE_PATH=$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  cd .. && pwd
)

source $REPO_BASE_PATH/.env
source $REPO_BASE_PATH/scripts/utils.sh

user_address=$(cast wallet address --private-key $user_private_key)

# Calculate the next expected contract address for the given deployer on both the C-chain and Subnet.
# These nonces/addresses will be used to deploy the VRF provider and proxy contracts to.
computed_provider_contract_address=$(cast compute-address $user_address --rpc-url $c_chain_url)
vrf_provider_address=$(parseComputedContractAddress "$computed_provider_contract_address")

computed_proxy_contract_address=$(cast compute-address $user_address --rpc-url $subnet_url)
vrf_proxy_address=$(parseComputedContractAddress "$computed_proxy_contract_address")

# Deploy the VRFProvider contract to the C-chain.
cd $REPO_BASE_PATH/contracts
forge create --private-key $user_private_key \
    src/VRFProvider.sol:VRFProvider \
    --constructor-args $c_chain_teleporter_registry_address $c_chain_vrf_coordinator_address $subnet_blockchain_id $vrf_proxy_address \
    --rpc-url $c_chain_url

# Deploy the VRFProxy contract to the Subnet.
forge create --private-key $user_private_key \
    src/VRFProxy.sol:VRFProxy \
    --constructor-args $subnet_teleporter_registry_address $c_chain_blockchain_id $vrf_provider_address \
    --rpc-url $subnet_url

# Deploy the SimpleBettingGame on the Subnet.
forge create --private-key $user_private_key \
  src/SimpleBettingGame.sol:SimpleBettingGame \
  --constructor-args $vrf_proxy_address $c_chain_vrf_subscription_id $c_chain_vrf_key_hash \
  --rpc-url $subnet_url
