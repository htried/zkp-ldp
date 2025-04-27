# ZK Proofs for IP addresses in private state credentials

This is a proof of concept for using zk proofs to verify ip addresses in private state credentials, as well as doing some basic risk scores/fingerprinting computations that may be useful.

The circom file `state.circom` brings together our different code for RAPPOR reporting, geographic distance checks and state fingerprinting. This circuit is used to update a stateful anonymous credential. To show that a user's credential is in a given state, a user must provide a signed hash of their current state (which the server has signed in a previous interaction).

A state consists of:
- The most recent N IP addresses used by the user (N is 5 for now)
- The most recent N geohashes corresponding to IPs used by the user.
- The most recent ``browser fingerprint'' state used by the user.
- A PRF seed (chosen by the client, they are incentivized to choose this well because this gives their DP answers privacy from randomness).
- A ``state counter'', which increments per every request the user has had. This gives domain separation for certain PRFs.
- It does NOT include a RAPPOR state since we don't need the PRR feature of RAPPOR

To update the state of a credential, the following information is needed:
- A new IP address to add to their state.
- The geohash associated with the location of that state, and a precision (precision is higher for IP addresses in densely populated locales)
- Fingerprinting information corresponding to the user's current browser.
- A new nonce for RAPPOR (provided in the server's previous response, used to randomize state and to seed RAPPOR)
- A new nonce for blinding the client's commitment (client-provided)

The proof does these computations:
- Check that the previous state was properly signed by the server.
- Verify signature from server's public key on new IP address/geohash information.
- Check that the distance between the two geohashes is within bounds.
- Check that the new browser fingerprint doesn't differ too much from the old one.
- Produce a RAPPOR randomized response using the correct randomness with relevant analytics.
- Update the state with the new IP address, geohash and old fingerprint.
- Compute nullifiers so a client can't reuse the same signed starting state more than once or the same server information response more than once.
- Output the RAPPOR response, the nullifiers, and a blinded commitment to the new state.

The prover sends the proof and public outputs to the server, and the server signs the new state for the prover.


## Setup

1. Install the circom library: `npm install -g circom` (if you're on Mac you may have to follow [these instructions](https://docs.circom.io/getting-started/installation/#installing-circom)).
2. Install the snarkjs library: `npm install -g snarkjs`
3. cd to the zk_cred_logic directory and run `git clone https://github.com/iden3/circomlib.git` to get the circom standard library installed.

## Running the code

1. Compile the circuit: `./shell/01_compile_circuit.sh state`
2. Run the powers of tau ceremony (this takes a while and requires some user-generated entropy): `./shell/02_powers_of_tau.sh state`

If you're running this for one input state, do the following:

3. Compute one witness file: `./shell/03_compute_one_witness.sh state input.json <output_witness_path>`. Sample input files are in `/test` and they were generated with `test_circom_state.js`.
4. Generate one proof given the witness: `./shell/04_generate_one_proof.sh state <witness_path> <output_proof_path> <output_public_path>`
5. Verify the proof: `./shell/05_verify_one_proof.sh <public_path> <proof_path>`

If you want to run the test suite, do the following:

8. `node test_circom_state.js` (This only needs steps 1 and 2 to be complete).
