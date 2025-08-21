#!/bin/bash

echo "Running trials and outputting to CSV..."
echo "trial,verification_ms,nullifier_ms,signing_ms,total_ms" > timing_results.csv

# Number of trials
TRIALS=200

# Run trials
for i in $(seq 1 $TRIALS); do
    echo -n "Trial $i/$TRIALS... "
    
    # Make the request and extract timing data
    response=$(curl -s -X POST http://localhost:8080/verify \
        -H "Content-Type: application/json" \
        -d '{
            "proof": '"$(cat circom_stuff/proof.json)"',
            "public_input": '"$(cat circom_stuff/public.json)"',
            "input": '"$(cat circom_stuff/test_input.json)"'
        }')
    
    # Extract timing values (convert from nanoseconds to milliseconds)
    verification_time=$(echo "$response" | jq -r '.timing.verification_time')
    nullifier_time=$(echo "$response" | jq -r '.timing.nullifier_time')
    signing_time=$(echo "$response" | jq -r '.timing.signing_time')
    total_time=$(echo "$response" | jq -r '.timing.total_time')
    
    # Output to CSV
    echo "$i,$verification_time,$nullifier_time,$signing_time,$total_time" >> timing_results.csv
    
    echo "✓ (${total_time}ms)"
    
    # Small delay to avoid overwhelming the server
    sleep 0.1
done

echo ""
echo "Results saved to timing_results.csv"
echo "First few lines:"
head -10 timing_results.csv
