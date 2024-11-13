#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No circuit file specified"
    echo "Usage: $0 <circuit_name> <witness_path> <output_proof_path> <output_public_path>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: No witness path specified"
    echo "Usage: $0 <circuit_name> <witness_path> <output_proof_path> <output_public_path>"
    exit 1
fi

if [ -z "$3" ]; then
    echo "Error: No output proof path specified"
    echo "Usage: $0 <circuit_name> <witness_path> <output_proof_path> <output_public_path>"
    exit 1
fi

if [ -z "$4" ]; then
    echo "Error: No output public path specified"
    echo "Usage: $0 <circuit_name> <witness_path> <output_proof_path> <output_public_path>"
    exit 1
fi

snarkjs groth16 prove "$1"_0001.zkey "$2" "$3" "$4"