## Running the experiments

1. Navigate to `shell/`  and run `./01_generate_witness.sh`, then `./02_generate_proof.sh`.
2. Run `go mod tidy` in the base of this directory to download golang prerequisites
3. Run `go build -o credential_server main.go` to compile the credential server
4. Run `./credential_server` to start the server
5. From a different terminal, run `./run_trials.sh` to run server-side trials.