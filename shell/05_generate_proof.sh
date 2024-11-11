#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No circuit file specified"
    echo "Usage: $0 <circuit_name>"
    exit 1
fi

snarkjs groth16 prove "$1"_0001.zkey witness.wtns proof.json public.json