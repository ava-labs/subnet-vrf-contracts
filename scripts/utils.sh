#!/usr/bin/env bash
# Copyright (C) 2024, Ava Labs, Inc. All rights reserved.
# See the file LICENSE for licensing terms.

function parseContractAddress() {
    echo $1 | ggrep -o -P 'Deployed to: .{42}' | sed 's/^.\{13\}//';
}

function parseComputedContractAddress() {
    echo $1 | ggrep -o -P 'Computed Address: .{42}' | sed 's/^.\{18\}//';
}