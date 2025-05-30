#!/bin/bash

# Usage: ./compile_experiment.sh <state_length>

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <state_length>"
    exit 1
fi

K=$1
CIRCUIT_NAME="state"
EXPERIMENT_DIR="$(dirname "$0")/k${K}"
EXPERIMENT_PARENT_DIR="$(dirname "$0")"
CIRCUIT_PATH="$EXPERIMENT_DIR/${CIRCUIT_NAME}.circom"
CONSTRAINTS_CSV_PATH="$(dirname "$0")/constraints.csv"

mkdir -p "$EXPERIMENT_DIR"

# 1. Generate a new circuit with state length K
cat > "$CIRCUIT_PATH" <<EOL
pragma circom 2.2.0;
include "../../state.circom";
component main = AttemptStateUpdate($K);
EOL

# 2. Compile the circuit
circom "$CIRCUIT_PATH" --r1cs --wasm --sym --c -o "$EXPERIMENT_DIR"

R1CS_FILE="$EXPERIMENT_DIR/${CIRCUIT_NAME}.r1cs"

# 3. Determine constraint size using provided constraints.csv if possible
NUM_CONSTRAINTS=""
if [ -f "$CONSTRAINTS_CSV_PATH" ]; then
    # Try to find the row for the given k
    CSV_ROW=$(awk -F, -v k="$K" 'NR>1 && $1==k {print $0}' "$CONSTRAINTS_CSV_PATH")
    if [ ! -z "$CSV_ROW" ]; then
        NON_LINEAR=$(echo "$CSV_ROW" | awk -F, '{print $3}')
        LINEAR=$(echo "$CSV_ROW" | awk -F, '{print $4}')
        NUM_CONSTRAINTS=$((NON_LINEAR + LINEAR))
        echo "Using constraints.csv: k=$K, non-linear=$NON_LINEAR, linear=$LINEAR, total=$NUM_CONSTRAINTS"
    fi
fi

# If not found in constraints.csv, export constraints and compute
if [ -z "$NUM_CONSTRAINTS" ]; then
    CONSTRAINTS_CSV="$EXPERIMENT_DIR/${CIRCUIT_NAME}_constraints.csv"
    if [ ! -f "$CONSTRAINTS_CSV" ]; then
        snarkjs r1cs export csv "$R1CS_FILE" "$CONSTRAINTS_CSV"
    fi
    NUM_CONSTRAINTS=$(awk -F, 'NR>1 {sum += $2 + $3} END {print sum}' "$CONSTRAINTS_CSV")
    echo "Using exported constraints.csv: total=$NUM_CONSTRAINTS"
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
PTAU_URL="https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_${POT_EXP}.ptau"
PTAU_FILE="$EXPERIMENT_DIR/pot${POT_EXP}_final.ptau"

# Download ptau file if not present
if [ ! -f "$PTAU_FILE" ]; then
    echo "Downloading ptau file: $PTAU_URL"
    curl -L "$PTAU_URL" -o "$PTAU_FILE"
fi

# 4. Trusted setup using downloaded ptau
snarkjs groth16 setup "$R1CS_FILE" "$PTAU_FILE" "$EXPERIMENT_DIR/${CIRCUIT_NAME}_0000.zkey"
snarkjs zkey contribute "$EXPERIMENT_DIR/${CIRCUIT_NAME}_0000.zkey" "$EXPERIMENT_DIR/${CIRCUIT_NAME}_0001.zkey" --name="1st Contributor Name"
snarkjs zkey export verificationkey "$EXPERIMENT_DIR/${CIRCUIT_NAME}_0001.zkey" "$EXPERIMENT_DIR/verification_key.json"