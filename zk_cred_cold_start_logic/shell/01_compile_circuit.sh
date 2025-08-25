#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No circuit file specified"
    echo "Usage: $0 <circuit_name>"
    exit 1
fi

circom "$1".circom --r1cs --wasm --sym --c -l ../self/node_modules -l ../self/node_modules/@zk-kit/binary-merkle-root.circom/src -l ../self/node_modules/circomlib/circuits
