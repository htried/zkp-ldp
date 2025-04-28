include "../circomlib/circuits/bitify.circom";
include "../circomlib/circuits/comparators.circom";
include "../circomlib/circuits/gates.circom";
include "../circomlib/circuits/poseidon.circom";


template InitializeEmptyState(num_ips) {
    signal input fingerprint[2];
    signal input users_prf_seed;
    signal input initial_comm_rand; 

    // Commitment to the client's new state which the server signs.
    signal output new_state_commitment;

    var len = num_ips + num_ips + 2 + 1 + 1;
    component state_hasher = Poseidon(len);

    // Add empty IP list to the state
    for (var i = 0; i < num_ips; i++) {
        state_hasher.inputs[i] <== 0;
    }
    // Add empty geohash list to the state
    for (var i = num_ips; i < 2*num_ips; i++) {
        state_hasher.inputs[i] <== 0;
    }
    state_hasher.inputs[2*num_ips] <== fingerprint[0];
    state_hasher.inputs[2*num_ips + 1] <== fingerprint[1];
    state_hasher.inputs[2*num_ips + 2] <== users_prf_seed;
    state_hasher.inputs[2*num_ips + 3] <== 0; // the state counter, starts at 0

    component comm_hasher = Poseidon(2);
    comm_hasher.inputs[0] <== initial_comm_rand;
    comm_hasher.inputs[1] <== state_hasher.out;

    new_state_commitment <== comm_hasher.out;
}

component main = InitializeEmptyState(5);