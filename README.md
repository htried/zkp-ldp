# ZK Proofs for IP addresses in private state credentials

This is a proof of concept for using zk proofs to verify ip addresses in private state credentials.

## Setup

1. Install the circom library: `npm install -g circom`
2. Install the snarkjs library: `npm install -g snarkjs`

## Running the code

1. Compile the circuit: `./shell/01_compile_circuit.sh state`
2. Generate an input file: `python3 update_in.py` (then follow the prompts in the terminal)
3. Compute the witness: `./shell/02_compute_witness.sh state`
4. Initialize the powers of tau ceremony: `./shell/03_powers_of_tau_zk_general.sh`
5. Generate and export the verification key: `./shell/04_powers_of_tau_zk_specific.sh state`
6. Generate the proof: `./shell/05_generate_proof.sh state`
7. Verify the proof: `./shell/06_verify_proof.sh`

For each IP address state update, re-run steps 2 through 7.
