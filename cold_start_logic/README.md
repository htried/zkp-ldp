## Summary
This is a smaller circuit which produces an initial state for a ``cold start'' (when a user first signs up with the service). It produces a commitment to a state with an empty list of IPs, geohashes and a 0 state counter. This is when the fingerprint and the PRF seed for generating commitments and randomness for RAPPOR are also committed to.

## Running the code

1. Compile the circuit: `./shell/01_compile_circuit.sh cold_start`
2. Run the powers of tau ceremony (this takes a while and requires some user-generated entropy): `./shell/02_powers_of_tau.sh state`
3. Node.