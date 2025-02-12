#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No public path specified"
    echo "Usage: $0 <public_path> <proof_path>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: No proof path specified"
    echo "Usage: $0 <public_path> <proof_path>"
    exit 1
fi

snarkjs groth16 verify verification_key.json "$1" "$2"