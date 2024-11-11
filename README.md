# ZK Proofs for IP addresses in private state credentials

This is a proof of concept for using zk proofs to verify ip addresses in private state credentials.

## Setup

1. Install the circom library: `npm install -g circom`
2. Install the snarkjs library: `npm install -g snarkjs`

## Running the code

1. Compile the circuit: `./shell/01_compile_circuit.sh state`
2. Run the powers of tau ceremony (this takes a while and requires some user-generated entropy): `./shell/02_powers_of_tau.sh state`

If you're running this for one input state, do the following:

3. Generate / update an input file: `python3 update_in.py` (then follow the prompts in the terminal)
4. Compute one witness file: `./shell/03_compute_one_witness.sh state input.json <output_witness_path>`
5. Generate one proof given the witness: `./shell/05_generate_one_proof.sh state <witness_path> <output_proof_path> <output_public_path>`
6. Verify the proof: `./shell/06_verify_one_proof.sh <public_path> <proof_path>`
7. For each IP address state update, re-run steps 3 through 6.

If you want to run the test suite, do the following:

8. Run the test suite: `./shell/06_test.sh state`
