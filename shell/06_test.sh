#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No circuit file specified"
    echo "Usage: $0 <circuit_name>"
    exit 1
fi

mkdir -p witnesses proofs publics

for file in test/*.json; do
    echo "Testing $file"
    witness_path="witnesses/$(basename "$file" .json).wtns"
    proof_path="proofs/$(basename "$file" .json).json"
    public_path="publics/$(basename "$file" .json).json"
    ./shell/03_compute_one_witness.sh "$1" "$file" "$witness_path"
    ./shell/04_generate_one_proof.sh "$1" "$witness_path" "$proof_path" "$public_path"
    ./shell/05_verify_one_proof.sh "$public_path" "$proof_path"
done