set -e

EXPERIMENT_PARENT_DIR="$(dirname "$0")"
N=101

node "$EXPERIMENT_PARENT_DIR/experiment_runner_streaming.js" "$N" "/Users/haltriedman/code/zkp-ldp/results/experiment_results_streaming.json"
echo "Streaming experiment complete. Results in /Users/haltriedman/code/zkp-ldp/results/experiment_results_streaming.json" 