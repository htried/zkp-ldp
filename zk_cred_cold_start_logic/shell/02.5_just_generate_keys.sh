#! /bin/bash

snarkjs groth16 setup "$1".r1cs ../pots/pot21_final.ptau "$1"_0000.zkey
snarkjs zkey contribute "$1"_0000.zkey "$1"_0001.zkey --name="1st Contributor Name" -v
snarkjs zkey export verificationkey "$1"_0001.zkey verification_key.json