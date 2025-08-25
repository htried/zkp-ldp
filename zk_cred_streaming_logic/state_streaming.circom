pragma circom 2.2.0;

include "../circomlib/circuits/bitify.circom";
include "../circomlib/circuits/comparators.circom";
include "../circomlib/circuits/gates.circom";
include "../circomlib/circuits/poseidon.circom";
include "../circomlib/circuits/babyjub.circom";
include "../circomlib/circuits/eddsaposeidon.circom";
include "../rappor_logic/rappor.circom";
// include "../circomlib/circuits/logic.circom";

// ============== STREAMING STATE STRUCT =================
bus StreamingCredentialState() {
    signal geohash_sum;
    signal state_counter;
    signal avg_geohash;
    signal last_fingerprint[2];
    signal yob[2];
    signal users_prf_seed;
    signal state_sig_r8x;
    signal state_sig_r8y;
    signal state_sig_s;
}

// ============== STATE MANAGEMENT FUNCTIONS =================

// Checks that the initial state has a valid signature and outputs a nullifier.
template ValidateInitialStreamingState() {
    signal input geohash_sum;
    signal input state_counter;
    signal input avg_geohash;
    signal input last_fingerprint[2];
    signal input yob[2];
    signal input users_prf_seed;
    signal input initial_state_r8x;
    signal input initial_state_r8y;
    signal input initial_state_s;
    signal input comm_rand;

    signal output nullifier;

    // Hash the state fields (include avg_geohash)
    signal state_hash_inputs[8];
    state_hash_inputs[0] <== geohash_sum;
    state_hash_inputs[1] <== state_counter;
    state_hash_inputs[2] <== avg_geohash;
    state_hash_inputs[3] <== last_fingerprint[0];
    state_hash_inputs[4] <== last_fingerprint[1];
    state_hash_inputs[5] <== yob[0];
    state_hash_inputs[6] <== yob[1];
    state_hash_inputs[7] <== users_prf_seed;
    component state_hasher = Poseidon(8);
    for (var i = 0; i < 8; i++) {
        state_hasher.inputs[i] <== state_hash_inputs[i];
    }

    component comm_hasher = Poseidon(2);
    comm_hasher.inputs[0] <== comm_rand;
    comm_hasher.inputs[1] <== state_hasher.out;

    // Verify initial state signature
    component initialVerifier = EdDSAPoseidonVerifier();
    initialVerifier.enabled <== 1;
    initialVerifier.M <== comm_hasher.out;
    initialVerifier.Ax <== 13277427435165878497778222415993513565335242147425444199013288855685581939618;
    initialVerifier.Ay <== 13622229784656158136036771217484571176836296686641868549125388198837476602820;
    initialVerifier.R8x <== initial_state_r8x;
    initialVerifier.R8y <== initial_state_r8y;
    initialVerifier.S <== initial_state_s;

    nullifier <== state_hasher.out;
}

// Checks that the server's response has a valid signature and outputs a nullifier.
template ValidateServerStreamingResponse() {
    signal input new_geohash;
    signal input new_rappor_nonce;
    signal input server_response_r8x;
    signal input server_response_r8y;
    signal input server_response_s;
    signal input users_prf_seed;
    signal input yob[2];

    signal output nullifier;

    component response_hasher = Poseidon(2);
    response_hasher.inputs[0] <== new_geohash;
    response_hasher.inputs[1] <== new_rappor_nonce;

    component responseVerifier = EdDSAPoseidonVerifier();
    responseVerifier.enabled <== 1;
    responseVerifier.M <== response_hasher.out;
    responseVerifier.Ax <== 13277427435165878497778222415993513565335242147425444199013288855685581939618;
    responseVerifier.Ay <== 13622229784656158136036771217484571176836296686641868549125388198837476602820;
    responseVerifier.R8x <== server_response_r8x;
    responseVerifier.R8y <== server_response_r8y;
    responseVerifier.S <== server_response_s;

    component nullifier_hasher = Poseidon(2);
    nullifier_hasher.inputs[0] <== users_prf_seed;
    nullifier_hasher.inputs[1] <== response_hasher.out;
    nullifier <== nullifier_hasher.out;
}

// Streaming state update logic
template CreateUpdatedStreamingState() {
    // Old state
    signal input geohash_sum;
    signal input state_counter;
    signal input users_prf_seed;
    signal input last_fingerprint[2];
    signal input yob[2];
    // New data
    signal input new_geohash;
    signal input new_fingerprint[2];
    signal input state_comm_randomness;
    signal input avg_geohash;

    // Output signals
    signal output new_state_commitment;
    signal output new_geohash_sum;
    signal output new_state_counter;
    signal output new_avg_geohash;
    signal output new_last_fingerprint[2];

    // Compute new state
    new_geohash_sum <== geohash_sum + new_geohash;
    new_state_counter <== state_counter + 1;
    new_avg_geohash <== avg_geohash;
    new_last_fingerprint <== new_fingerprint;

    // Enforce avg_geohash = floor(new_geohash_sum / new_state_counter)
    signal remainder;
    remainder <== new_geohash_sum - avg_geohash * new_state_counter;
    component rem_lt = LessThan(64);
    rem_lt.in[0] <== remainder;
    rem_lt.in[1] <== new_state_counter;
    rem_lt.out === 1;

    // Output state commitment (include avg_geohash)
    signal state_hash_inputs[8];
    state_hash_inputs[0] <== new_geohash_sum;
    state_hash_inputs[1] <== new_state_counter;
    state_hash_inputs[2] <== avg_geohash;
    state_hash_inputs[3] <== new_last_fingerprint[0];
    state_hash_inputs[4] <== new_last_fingerprint[1];
    state_hash_inputs[5] <== yob[0];
    state_hash_inputs[6] <== yob[1];
    state_hash_inputs[7] <== users_prf_seed;
    component state_hasher = Poseidon(8);
    for (var i = 0; i < 8; i++) {
        state_hasher.inputs[i] <== state_hash_inputs[i];
    }
    component comm_hasher = Poseidon(2);
    comm_hasher.inputs[0] <== state_comm_randomness;
    comm_hasher.inputs[1] <== state_hasher.out;
    new_state_commitment <== comm_hasher.out;
}

// Main streaming state update template
template AttemptStreamingStateUpdate() {
    // Inputs for previous state
    signal input geohash_sum;
    signal input state_counter;
    signal input avg_geohash;
    signal input last_fingerprint[2];
    signal input yob[2];
    signal input users_prf_seed;
    signal input initial_state_r8x;
    signal input initial_state_r8y;
    signal input initial_state_s;
    signal input initial_comm_rand;

    // Inputs for new state
    signal input new_geohash;
    signal input new_rappor_nonce;
    signal input new_user_info_r8x;
    signal input new_user_info_r8y;
    signal input new_user_info_s;
    signal input state_comm_randomness;
    signal input new_fingerprint[2];
    signal input next_avg_geohash;

    // Outputs
    signal output old_state_nullifier;
    signal output server_response_nullifier;
    signal output new_state_commitment;
    signal output new_geohash_sum;
    signal output new_state_counter;
    signal output new_avg_geohash;
    signal output new_last_fingerprint[2];
    signal output rappor_response;

    // Validate initial state
    component initialStateValidator = ValidateInitialStreamingState();
    initialStateValidator.geohash_sum <== geohash_sum;
    initialStateValidator.state_counter <== state_counter;
    initialStateValidator.avg_geohash <== avg_geohash;
    initialStateValidator.last_fingerprint <== last_fingerprint;
    initialStateValidator.yob <== yob;
    initialStateValidator.users_prf_seed <== users_prf_seed;
    initialStateValidator.initial_state_r8x <== initial_state_r8x;
    initialStateValidator.initial_state_r8y <== initial_state_r8y;
    initialStateValidator.initial_state_s <== initial_state_s;
    initialStateValidator.comm_rand <== initial_comm_rand;
    old_state_nullifier <== initialStateValidator.nullifier;

    // Validate server response
    component serverResponseValidator = ValidateServerStreamingResponse();
    serverResponseValidator.new_geohash <== new_geohash;
    serverResponseValidator.new_rappor_nonce <== new_rappor_nonce;
    serverResponseValidator.server_response_r8x <== new_user_info_r8x;
    serverResponseValidator.server_response_r8y <== new_user_info_r8y;
    serverResponseValidator.server_response_s <== new_user_info_s;
    serverResponseValidator.yob <== yob;
    serverResponseValidator.users_prf_seed <== users_prf_seed;
    server_response_nullifier <== serverResponseValidator.nullifier;

    // Enforce avg_geohash = floor(geohash_sum / state_counter) (if state_counter > 0)
    signal remainder;
    remainder <== geohash_sum - avg_geohash * state_counter;
    component rem_lt = LessThan(64);
    rem_lt.in[0] <== remainder;
    rem_lt.in[1] <== state_counter;
    rem_lt.out === 1;

    // Compute bits for prefix comparison
    signal avg_geohash_bits[64] <== Num2Bits(64)(avg_geohash);
    signal new_geohash_bits[64] <== Num2Bits(64)(new_geohash);

    // Compare prefix bits (e.g., first 20 bits)
    var geohash_shared_bits = 20;
    component bit_equals[geohash_shared_bits];
    component all_bits_equal = MultiAND(geohash_shared_bits);
    for (var i = 0; i < geohash_shared_bits; i++) {
        bit_equals[i] = IsEqual();
        bit_equals[i].in[0] <== avg_geohash_bits[64 - geohash_shared_bits + i];
        bit_equals[i].in[1] <== new_geohash_bits[64 - geohash_shared_bits + i];
        all_bits_equal.in[i] <== bit_equals[i].out;
    }
    all_bits_equal.out === 1;

    // Update state
    component updateState = CreateUpdatedStreamingState();
    updateState.geohash_sum <== geohash_sum;
    updateState.state_counter <== state_counter;
    updateState.yob <== yob;
    updateState.users_prf_seed <== users_prf_seed;
    updateState.last_fingerprint <== last_fingerprint;
    updateState.new_geohash <== new_geohash;
    updateState.new_fingerprint <== new_fingerprint;
    updateState.state_comm_randomness <== state_comm_randomness;
    updateState.avg_geohash <== next_avg_geohash;
    new_state_commitment <== updateState.new_state_commitment;
    new_geohash_sum <== updateState.new_geohash_sum;
    new_state_counter <== updateState.new_state_counter;
    new_avg_geohash <== updateState.new_avg_geohash;
    new_last_fingerprint <== updateState.new_last_fingerprint;

    // RAPPOR reporting logic (streaming version)
    var num_hashes = 2;
    var num_bloombits = 16;
    var log_bloombits = 4;
    signal empty_bloom_filter[num_bloombits];
    for (var i = 0; i < num_bloombits; i++) {
        empty_bloom_filter[i] <== 0;
    }

    // Produce p,q randomness for IRR
    component rappor_randomness_hasher_1 = Poseidon(3);
    rappor_randomness_hasher_1.inputs[0] <== users_prf_seed;
    rappor_randomness_hasher_1.inputs[1] <== new_rappor_nonce;
    rappor_randomness_hasher_1.inputs[2] <== state_counter;
    component rappor_randomness_hasher_2 = Poseidon(2);
    rappor_randomness_hasher_2.inputs[0] <== users_prf_seed;
    rappor_randomness_hasher_2.inputs[1] <== rappor_randomness_hasher_1.out;

    // Add streaming state values to bloom filter
    component add_state_counter_to_filter = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_state_counter_to_filter.initial_filter <== empty_bloom_filter;
    add_state_counter_to_filter.new_value <== state_counter;
    component add_avg_geohash_to_filter = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_avg_geohash_to_filter.initial_filter <== add_state_counter_to_filter.new_filter;
    add_avg_geohash_to_filter.new_value <== avg_geohash;

    // Optionally, add fingerprint similarity or other metrics here
    // For now, just use state_counter and avg_geohash

    component randomize_bloom_filter = IndividualRandomizedResponse(num_bloombits);
    randomize_bloom_filter.prr <== add_avg_geohash_to_filter.new_filter;
    randomize_bloom_filter.p_randomness <== rappor_randomness_hasher_1.out;
    randomize_bloom_filter.q_randomness <== rappor_randomness_hasher_2.out;

    component irr_to_num = Bits2Num(num_bloombits);
    irr_to_num.in <== randomize_bloom_filter.irr;
    rappor_response <== irr_to_num.out;

    // Check that yob implies that user is over 18.
    // This looks slightly weird, the reason is that Year of Birth is encoded as 
    // 2 ASCII bytes of the digit values. The default value in the test data is 00
    // for 2000, so 48, 48.s
    signal yob_0_digit <== yob[0] - 48;
    signal yob_1_digit <== yob[1] - 48;
    signal yob_2_digit_value <== yob_0_digit * 10 + yob_1_digit;

    // Sanity check that yob is below 100.
    component yob_range_check = LessThan(7);
    yob_range_check.in[0] <== yob_2_digit_value;
    yob_range_check.in[1] <== 100;
    yob_range_check.out === 1;

    // If you were born before 2007, it would be 07 and thus you are of age.
    component yob_21st_century_of_age = LessThan(7);
    yob_21st_century_of_age.in[0] <== yob_2_digit_value;
    yob_21st_century_of_age.in[1] <== 7;

    // If you were born before after 1926, it would be 26+ and thus you are of age.
    component yob_20th_century_of_age = LessThan(7);
    yob_20th_century_of_age.in[0] <== 25;
    yob_20th_century_of_age.in[1] <== yob_2_digit_value;

    signal of_age <== OR()(yob_20th_century_of_age.out, yob_21st_century_of_age.out);
    of_age === 1;
}

component main = AttemptStreamingStateUpdate();
