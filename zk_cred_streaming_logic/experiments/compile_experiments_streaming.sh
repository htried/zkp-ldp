#!/bin/bash

# Usage: ./compile_experiment.sh <ldp>

set -e

CIRCUIT_PATH="state_streaming.circom"
CONSTRAINTS_CSV_PATH="$(dirname "$0")/constraints.csv"

# 2. Compile the circuit and capture output
echo "Compiling circuit with circom..."
CIRCOM_OUTPUT=$(circom "$CIRCUIT_PATH" --r1cs --wasm --sym --c -o . 2>&1 | tee /dev/tty)

R1CS_FILE="state_streaming.r1cs"

# 3. Determine constraint size using provided constraints.csv if possible
NUM_CONSTRAINTS=""
if [ -f "$CONSTRAINTS_CSV_PATH" ]; then
    # Try to find the row for the given k
    CSV_ROW=$(awk -F, -v k="$K" 'NR>1 && $1==k {print $0}' "$CONSTRAINTS_CSV_PATH")
    if [ ! -z "$CSV_ROW" ]; then
        NUM_CONSTRAINTS=$(echo "$CSV_ROW" | awk -F, '{print $2}')
        echo "Using constraints.csv: k=$K, total=$NUM_CONSTRAINTS"
    fi
fi

# If not found in constraints.csv, parse circom output for constraints
if [ -z "$NUM_CONSTRAINTS" ]; then
    # Extract non-linear and linear constraints from circom output
    # Use more specific patterns to avoid overlap
    NON_LINEAR=$(echo "$CIRCOM_OUTPUT" | grep -i "^.*non-linear constraints:" | head -1 | awk -F: '{gsub(/ /,"",$2); print $2}')
    LINEAR=$(echo "$CIRCOM_OUTPUT" | grep -i "^.*linear constraints:" | grep -v "non-linear" | head -1 | awk -F: '{gsub(/ /,"",$2); print $2}')
    
    # Remove any non-digit characters and ensure we have valid numbers
    NON_LINEAR_NUM=$(echo "$NON_LINEAR" | tr -cd '0-9')
    LINEAR_NUM=$(echo "$LINEAR" | tr -cd '0-9')
        
    # Check if we have valid numbers and convert to integers
    if [[ -n "$NON_LINEAR_NUM" && -n "$LINEAR_NUM" && "$NON_LINEAR_NUM" =~ ^[0-9]+$ && "$LINEAR_NUM" =~ ^[0-9]+$ ]]; then
        # Force conversion to integers using arithmetic expansion
        NUM_CONSTRAINTS=$((10#$NON_LINEAR_NUM + 10#$LINEAR_NUM))
        echo "Using circom output: total=$NUM_CONSTRAINTS"
        echo "$K,$NUM_CONSTRAINTS,$ldp" >> "$CONSTRAINTS_CSV_PATH"
    else
        echo "Error: Could not determine constraint counts from circom output."
        echo "Circom output:"
        echo "$CIRCOM_OUTPUT"
        exit 1
    fi
fi

# Compute next power of two
next_power_of_two() {
    local n=$1
    local p=1
    while [ $p -lt $n ]; do
        p=$((p * 2))
    done
    echo $p
}

# Compute exponent from power of two
power_of_two_exponent() {
    local n=$1
    local exp=0
    while [ $n -gt 1 ]; do
        n=$((n / 2))
        exp=$((exp + 1))
    done
    echo $exp
}

POT_SIZE=$(next_power_of_two $NUM_CONSTRAINTS)
POT_EXP=$(power_of_two_exponent $POT_SIZE)
# POT_EXP=16
PTAU_URL="https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_${POT_EXP}.ptau"
PTAU_FILE="../pots/pot${POT_EXP}_final.ptau"

# Download ptau file if not present
if [ ! -f "$PTAU_FILE" ]; then
    echo "Downloading ptau file: $PTAU_URL"
    curl -L "$PTAU_URL" -o "$PTAU_FILE"
fi

# 4. Trusted setup using downloaded ptau
snarkjs groth16 setup "$R1CS_FILE" "$PTAU_FILE" "state_streaming_0000.zkey"
snarkjs zkey contribute "state_streaming_0000.zkey" "state_streaming_0001.zkey" --name="1st Contributor Name"
snarkjs zkey export verificationkey "state_streaming_0001.zkey" "verification_key.json"

node "state_streaming_js/generate_witness.js" "state_streaming_js/state_streaming.wasm" "input.json" "witness.wtns"

