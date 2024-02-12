#!/usr/bin/env bash
# Copyright (C) 2024, Ava Labs, Inc. All rights reserved.
# See the file LICENSE for licensing terms.

set -e

REPO_BASE_PATH=$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  cd .. && pwd
)

function solFormat() {
    # format solidity contracts
    echo "Formatting Solidity contracts..."
    forge fmt --root $REPO_BASE_PATH/contracts $REPO_BASE_PATH/contracts/src/**
}

function solFormatCheck() {
    # format solidity contracts
    echo "Checking formatting of Solidity contracts..."
    forge fmt --check --root $REPO_BASE_PATH/contracts $REPO_BASE_PATH/contracts/src/**
}

function solLinter() {
    # lint solidity contracts
    echo "Linting Solidity contracts..."
    cd $REPO_BASE_PATH/contracts/src
    # "solhint **/*.sol" runs differently than "solhint '**/*.sol'", where the latter checks sol files
    # in subdirectories. The former only checks sol files in the current directory and directories one level down.
    solhint '**/*.sol' --config ./.solhint.json --ignore-path ./.solhintignore --max-warnings 0
}

function runAll() {
    solFormat
    solLinter
}

function printHelp() {
    echo "Usage: ./scripts/lint.sh [OPTIONS]"
    echo "Lint/Format solidity contracts."
    printUsage
}

function printUsage() {
    echo "Options:"
    echo "  -sfc, --sol-format-check            Check for proper formatted Solidity files. Exits with code 1 if not."
    echo "  -sf,  --sol-format                  Format Solidity contracts"
    echo "  -sl,  --sol-lint                    Run the Solidity linter"
    echo "  -h,   --help                        Print this help message"
}

# if we have no args, perform all checks
if [ $# -eq 0 ]; then
    runAll
    exit 0
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -sfc | --sol-format-check) 
            solFormatCheck ;;
        -sf  | --sol-format) 
            solFormat ;;
        -sl  | --sol-lint) 
            solLinter ;;
        -h   | --help) 
            printHelp ;;
        *) 
          echo "Invalid option: -$1" && printHelp && exit 1;;
    esac
    shift
done


exit 0