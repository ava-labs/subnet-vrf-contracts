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

# Calculate the next expected contract address for the given deployer on both the C-Chain and Subnet.
# These nonces/addresses will be used to deploy the VRF provider and proxy contracts to.
computed_provider_contract_address=$(cast compute-address $user_address --rpc-url $c_chain_url)
vrf_provider_address=$(parseComputedContractAddress "$computed_provider_contract_address")

computed_proxy_contract_address=$(cast compute-address $user_address --rpc-url $subnet_url)
vrf_proxy_address=$(parseComputedContractAddress "$computed_proxy_contract_address")

# Deploy the VRFProvider contract to the C-Chain.
cd $REPO_BASE_PATH/contracts
echo "Deploying VRFProvider to C-Chain..."
forge create --private-key $user_private_key \
    src/VRFProvider.sol:VRFProvider \
    --constructor-args $c_chain_teleporter_registry_address $c_chain_vrf_coordinator_address $subnet_blockchain_id $vrf_proxy_address \
    --rpc-url $c_chain_url > /dev/null
echo "Deployed VRFProvider to C-Chain."

# Deploy the VRFProxy contract to the Subnet.
echo "Deploying VRFProxy to Subnet..."
forge create --private-key $user_private_key \
    src/VRFProxy.sol:VRFProxy \
    --constructor-args $subnet_teleporter_registry_address $c_chain_blockchain_id $vrf_provider_address \
    --rpc-url $subnet_url > /dev/null
echo "Deployed VRFProxy to Subnet."

# Deploy the SimpleBettingGame on the Subnet.
echo "Deploying SimpleBettingGame to Subnet..."
simple_betting_game_deploy_result=$(forge create --private-key $user_private_key \
  src/SimpleBettingGame.sol:SimpleBettingGame \
  --constructor-args $vrf_proxy_address $c_chain_vrf_subscription_id $c_chain_vrf_key_hash \
  --rpc-url $subnet_url)
simple_betting_game_address=$(parseContractAddress "$simple_betting_game_deploy_result")
echo "Deployed SimpleBettingGame to Subnet."

echo "Finished deploying contracts."
echo "C-Chain VRFProvider: $vrf_provider_address"
echo "Subnet VRFProxy: $vrf_proxy_address"
echo "Subnet SimpleBettingGame: $simple_betting_game_address"
