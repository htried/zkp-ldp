set -e

EXPERIMENT_PARENT_DIR="$(dirname "$0")"
N=100

for K in 5; do
    echo "Running $N experiments for K = $K"
    EXPERIMENT_DIR="$(dirname "$0")/k${K}"
    node "$EXPERIMENT_PARENT_DIR/experiment_runner.js" "$K" "$N" "$EXPERIMENT_DIR/experiment_results_success_k${K}_N${N}.json" "success"
    echo "Experiment complete. Results in $EXPERIMENT_DIR/experiment_results_success_k${K}_N${N}.json" 
done
