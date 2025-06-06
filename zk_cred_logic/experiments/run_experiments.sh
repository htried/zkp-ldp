set -e

EXPERIMENT_PARENT_DIR="$(dirname "$0")"
N=100

for K in 5 10 25 50 100 250 500 1000 2500 5000; do
    echo "Running $N experiments for K = $K"
    EXPERIMENT_DIR="$(dirname "$0")/k${K}"
    node "$EXPERIMENT_PARENT_DIR/experiment_runner.js" "$K" "$N" "$EXPERIMENT_PARENT_DIR/results_attribution_single/experiment_results_k${K}.json" "success"
    echo "Experiment complete. Results in $EXPERIMENT_PARENT_DIR/results_attribution_single/experiment_results_k${K}.json" 
done
