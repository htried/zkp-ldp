#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No circuit file specified"
    echo "Usage: $0 <circuit_name>"
    exit 1
fi

node "$1"_js/generate_witness.js "$1"_js/"$1".wasm input.json witness.wtns