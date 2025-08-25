#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No circuit file specified"
    echo "Usage: $0 <circuit_name>"
    exit 1
fi

snarkjs powersoftau new bn128 16 pot12_0000.ptau -v

snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="First contribution" -v

snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau -v

snarkjs groth16 setup "$1".r1cs pot12_final.ptau "$1"_0000.zkey

snarkjs zkey contribute "$1"_0000.zkey "$1"_0001.zkey --name="1st Contributor Name" -v

snarkjs zkey export verificationkey "$1"_0001.zkey verification_key.json