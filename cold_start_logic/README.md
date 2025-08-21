## Summary
This is a smaller circuit which produces an initial state for a ``cold start'' (when a user first signs up with the service). It produces a commitment to a state with an empty list of IPs, geohashes and a 0 state counter. This is when the fingerprint and the PRF seed for generating commitments and randomness for RAPPOR are also committed to.

## Running the code

1. Compile the circuit: `./shell/01_compile_circuit.sh cold_start`
2. Make sure that the powers of tau output for circuits on the order of 2^21 is downloaded to `zkp-ldp/pots/pot21_final.ptau`. You can find that file at this link: https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_21.ptau. Then you can run `./shell/02.5_just_generate_keys.sh cold_start`, which will output relevant circom outputs.
    - (Alternatively) Run the powers of tau ceremony (this will take a while and requires some user-generated entropy): `./shell/02_powers_of_tau.sh cold_start`
3. Run `./shell/03_compute_one_witness.sh cold_start input.json witness.wtns`. This calculates a witness on the provided input in this directory.
4. Run `npm install` to install all relevant node packages
5. Run `node test_cold_start.js` to run 100 trials on your device. The results will be output in a JSON file.