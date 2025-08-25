set -e

EXPERIMENT_PARENT_DIR="$(dirname "$0")"
N=100

node "$EXPERIMENT_PARENT_DIR/experiment_runner_streaming.js" "$N" "$EXPERIMENT_PARENT_DIR/experiment_results_streaming_N${N}.json"
echo "Streaming experiment complete. Results in $EXPERIMENT_PARENT_DIR/experiment_results_streaming_N${N}.json" 