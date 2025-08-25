#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: No circuit file specified"
    echo "Usage: $0 <circuit_name> <input_json_path> <output_witness_path>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: No input json path specified"
    echo "Usage: $0 <circuit_name> <input_json_path> <output_witness_path>"
    exit 1
fi

if [ -z "$3" ]; then
    echo "Error: No output witness path specified"
    echo "Usage: $0 <circuit_name> <input_json_path> <output_witness_path>"
    exit 1
fi

node "$1"_js/generate_witness.js "$1"_js/"$1".wasm "$2" "$3"