#!/bin/bash

INPUT_JSON="${1:-../circom_stuff/test_input.json}"
OUTPUT_WITNESS="${2:-../circom_stuff/witness.wtns}"

echo "Generating witness from input: $INPUT_JSON"
echo "Output witness: $OUTPUT_WITNESS"

# Generate witness using the state circuit
node ../circom_stuff/state_js/generate_witness.js ../circom_stuff/state_js/state.wasm "$INPUT_JSON" "$OUTPUT_WITNESS"

if [ $? -eq 0 ]; then
    echo "Witness generated successfully: $OUTPUT_WITNESS"
else
    echo "Error generating witness"
    exit 1
fi
