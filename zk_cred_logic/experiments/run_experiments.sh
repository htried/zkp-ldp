set -e

EXPERIMENT_PARENT_DIR="$(dirname "$0")"
N=100

# for K in 1 5 10 25 50 100 250 500 1000 2500 5000; do
for K in 5000; do
    echo "Running experiments for K = $K"
    node "$EXPERIMENT_PARENT_DIR/experiment_runner.js" "$K" "$N"
    echo "Experiment complete. Results in $EXPERIMENT_PARENT_DIR/k${K}/experiment_results_k${K}.json" 
done
