pragma circom 2.2.0;

include "../circomlib/circuits/bitify.circom";
include "../circomlib/circuits/comparators.circom";
include "../circomlib/circuits/gates.circom";
include "../circomlib/circuits/poseidon.circom";
include "../circomlib/circuits/babyjub.circom";
include "../circomlib/circuits/pedersen.circom";
include "../circomlib/circuits/eddsaposeidon.circom";
include "../rappor_logic/rappor.circom";
include "../geohash_logic/geohash.circom";
include "../fingerprint_logic_circom/fingerprint_distance_measurement.circom";

// ============== LOGICAL CIRCUIT COMPONENTS =================
template Mux1_2Vals() {
    signal input c;  // Control signal
    signal input a[2];  // Output this signal when c is 1
    signal input b[2];  // Output this signal when c is 0
    signal output out[2];

    // Ensure c is binary (0 or 1)
    c * (c - 1) === 0;

    // Constraint for multiplexing
    out[0] <== c * (a[0] - b[0]) + b[0];
    out[1] <== c * (a[1] - b[1]) + b[1];
}

// STATE STRUCT

bus CredentialState(num_ips){
    signal ips[num_ips];
    signal geohashes[num_ips];
    signal last_fingerprint[2];
    signal year_of_birth[2];
    signal users_prf_seed;
    signal state_counter;
    signal state_sig_r8x;
    signal state_sig_r8y;
    signal state_sig_s;
}

// ============== STATE MANAGEMENT FUNCTIONS =================

// Checks that the initial state has a valid signature and outputs
// a nullifier.
template ValidateInitialState(num_ips) {
    // Initial signed state
    signal input ips[num_ips];
    signal input geohashes[num_ips];
    signal input last_fingerprint[2];
    signal input yob[2];
    signal input users_prf_seed;
    signal input state_counter; 
    signal input initial_state_r8x;
    signal input initial_state_r8y;
    signal input initial_state_s;
    // nonce to use to produce commitment to state that the server signs.
    signal input comm_rand;

    signal output nullifier;

    var len = num_ips + num_ips + 2 + 2 + 1 + 1;
    signal state_hash_inputs[len];
    for (var i = 0; i < num_ips; i++) {
        state_hash_inputs[i] <== ips[i];
    }
    for (var i = 0; i < num_ips; i++) {
        state_hash_inputs[num_ips + i] <== geohashes[i];
    }
    state_hash_inputs[2*num_ips] <== last_fingerprint[0];
    state_hash_inputs[2*num_ips + 1] <== last_fingerprint[1];
    state_hash_inputs[2*num_ips + 2] <== yob[0];
    state_hash_inputs[2*num_ips + 3] <== yob[1];
    state_hash_inputs[2*num_ips + 4] <== users_prf_seed;
    state_hash_inputs[2*num_ips + 5] <== state_counter;
    component state_hasher = ChainedPoseidonHash(len);
    state_hasher.in <== state_hash_inputs;

    component comm_hasher = Poseidon(2);
    comm_hasher.inputs[0] <== comm_rand;
    comm_hasher.inputs[1] <== state_hasher.out;

    // log("comm_hasher.out");
    // log(comm_hasher.out);

    // Verify initial state signature
    component initialVerifier = EdDSAPoseidonVerifier();
    initialVerifier.enabled <== 1;
    initialVerifier.M <== comm_hasher.out;
    initialVerifier.Ax <== 13277427435165878497778222415993513565335242147425444199013288855685581939618;
    initialVerifier.Ay <== 13622229784656158136036771217484571176836296686641868549125388198837476602820;
    initialVerifier.R8x <== initial_state_r8x;
    initialVerifier.R8y <== initial_state_r8y;
    initialVerifier.S <== initial_state_s;
    
    // Nullifier is just regular state hash, signed response is a commitment.
    nullifier <== state_hasher.out;
}

// Checks that the server's response has a valid signature and outputs
// a nullifier.
template ValidateServerResponse() {
    // Initial signed state
    signal input new_ip;
    signal input new_geohash;
    signal input new_rappor_nonce;
    signal input new_fingerprint_nonce;
    signal input server_response_r8x;
    signal input server_response_r8y;
    signal input server_response_s;
    // nonce to use to produce nullifier.
    signal input users_prf_seed;

    signal output nullifier;

    var len = 1 + 1 + 1 + 1;
    component response_hasher = Poseidon(len);
    response_hasher.inputs[0] <== new_ip;
    response_hasher.inputs[1] <== new_geohash;
    response_hasher.inputs[2] <== new_rappor_nonce;
    response_hasher.inputs[3] <== new_fingerprint_nonce;

    // Verify initial state signature
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

// Does the logic to produce an updated state.
template CreateUpdatedState(num_ips) {
    // Old state
    signal input initialState_ips[num_ips];
    signal input initialState_geohashes[num_ips];
    signal input yob[2];
    signal input users_prf_seed;
    signal input state_counter;
    // Stuff to add to new state
    signal input new_ip;
    signal input new_geohash;
    signal input new_fingerprint[2];
    // Randomness for comm to new state:
    signal input state_comm_randomness;

    // Output signals
    signal output new_state_commitment;

    // Parts of the new state
    signal newState_ips[num_ips];
    signal newState_geohashes[num_ips];
    signal new_user_prf_seed <== users_prf_seed;
    signal new_last_fingerprint[2] <== new_fingerprint;
    signal new_state_counter <== state_counter + 1;

    // Pre-declare components for IP state update logic
    signal exists_binary;
    signal exists_zero;
    component isZero[num_ips];
    component notFirstZero[num_ips];
    component zeroAnds[num_ips - 1];
    component mux1[num_ips];
    component mux2[num_ips];
    component mux3[num_ips];
    component ipEqual[num_ips];

    // Initialize components and check for IP existence first
    component exists_ors[num_ips];
    exists_ors[0] = OR();
    exists_ors[0].a <== 0;
    // Not first zero is an array of OR()'s which is an array of 0's followed by 1's after the first zero entry.
    // Checking notFirstZero[j-1] == 0 ensures that ips[j] is the first zero.
    notFirstZero[0] = OR();
    notFirstZero[0].a <== 0;
    for (var j = 0; j < num_ips; j++) {
        isZero[j] = IsZero();
        ipEqual[j] = IsEqual();
        
        // Check IP equality once
        ipEqual[j].in[0] <== initialState_ips[j];
        ipEqual[j].in[1] <== new_ip;
        
        isZero[j].in <== initialState_ips[j];
        notFirstZero[j].b <== isZero[j].out;
        exists_ors[j].b <== ipEqual[j].out;
        if (j < (num_ips - 1)) {
            exists_ors[j+1] = OR();
            exists_ors[j+1].a <== exists_ors[j].out;
            notFirstZero[j+1] = OR();
            notFirstZero[j+1].a <== notFirstZero[j].out;
        }
    }

    // Move exists_binary assignment outside the loops
    exists_binary <== exists_ors[num_ips - 1].out;
    exists_zero <== notFirstZero[num_ips - 1].out;

    // Process IP updates
    // Explanation of logic:
    // First, if the IP is already in the state, then do nothing.
    // Otherwise, if there is a zero available, then put the new IP into the empty slot.
    // Last, if no zeros available, and IP not in state then move each IP up in state and then insert the last one.
    // Note that this code satisfies the invariant that the value in index i of geohashes
    // Corresponds to the IP in index i of IPs.
    for (var i = 0; i < num_ips; i++) {
        mux1[i] = Mux1_2Vals();
        mux2[i] = Mux1_2Vals();
        mux3[i] = Mux1_2Vals();
        
        if (i == 0) {
            mux1[i].c <== isZero[i].out;
            mux1[i].a[0] <== new_ip;
            mux1[i].a[1] <== new_geohash;
            mux1[i].b[0] <== initialState_ips[i];
            mux1[i].b[1] <== initialState_geohashes[i];
        } else {
            zeroAnds[i-1] = AND();
            zeroAnds[i-1].a <== (1-notFirstZero[i-1].out);
            zeroAnds[i-1].b <== isZero[i].out;
            mux1[i].c <== zeroAnds[i-1].out;
            mux1[i].a[0] <== new_ip;
            mux1[i].a[1] <== new_geohash;
            mux1[i].b[0] <== initialState_ips[i];
            mux1[i].b[1] <== initialState_geohashes[i];
        }
        
        mux2[i].c <== exists_zero;
        mux2[i].a <== mux1[i].out;
        mux2[i].b[0] <== i == num_ips-1 ? new_ip : initialState_ips[i+1];
        mux2[i].b[1] <== i == num_ips-1 ? new_geohash : initialState_geohashes[i+1];

        mux3[i].c <== exists_binary;
        mux3[i].a[0] <== initialState_ips[i];
        mux3[i].a[1] <== initialState_geohashes[i];
        mux3[i].b <== mux2[i].out;
        newState_ips[i] <== mux3[i].out[0];
        newState_geohashes[i] <== mux3[i].out[1];
    }
    
    var len = num_ips + num_ips + 2 + 2 + 1 + 1;
    signal new_state_hash_inputs[len];
    for (var i = 0; i < num_ips; i++) {
        new_state_hash_inputs[i] <== newState_ips[i];
    }
    for (var i = 0; i < num_ips; i++) {
        new_state_hash_inputs[num_ips + i] <== newState_geohashes[i];
    }
    new_state_hash_inputs[2*num_ips] <== new_last_fingerprint[0];
    new_state_hash_inputs[2*num_ips + 1] <== new_last_fingerprint[1];
    new_state_hash_inputs[2*num_ips + 2] <== yob[0];
    new_state_hash_inputs[2*num_ips + 3] <== yob[1];
    new_state_hash_inputs[2*num_ips + 4] <== new_user_prf_seed;
    new_state_hash_inputs[2*num_ips + 5] <== new_state_counter;
    component new_state_hasher = ChainedPoseidonHash(len);
    new_state_hasher.in <== new_state_hash_inputs;

    component comm_hasher = Poseidon(2);
    comm_hasher.inputs[0] <== state_comm_randomness;
    comm_hasher.inputs[1] <== new_state_hasher.out;

    new_state_commitment <== comm_hasher.out;
}

template AttemptStateUpdate(num_ips) {
    // Inputs corresponding to previous state
    signal input ips[num_ips];
    signal input geohashes[num_ips];
    signal input last_fingerprint[2];
    signal input yob[2];
    signal input users_prf_seed;
    signal input state_counter;
    signal input initial_state_r8x;
    signal input initial_state_r8y;
    signal input initial_state_s;
    signal input initial_comm_rand;

    // Inputs corresponding to new state.
    // The bits that the server provides are signed by the server.
    signal input new_ip;
    signal input new_geohash;
    signal input new_rappor_nonce;
    signal input new_user_info_r8x;
    signal input new_user_info_r8y;
    signal input new_user_info_s;

    // User provided inputs (unauthenticated)
    // User-provided blind for new state
    signal input state_comm_randomness;
    // Browser-provided new fingerprint.
    signal input new_fingerprint[2];
    signal input new_fingerprint_nonce;

    // Outputs
    // Nullifier so a client can't reuse a previously used state.
    signal output old_state_nullifier;
    // Nullifier so a client can't reuse a previous server response.
    signal output server_response_nullifier;
    // Commitment to the client's new state which the server signs.
    signal output new_state_commitment;
    //Commitment to the client's fingerprint.
    signal output new_fingerprint_commitment;

    // Rappor reporting data
    signal output rappor_response;

    // Validate initial state and produce nullifier.
    component initialStateValidator = ValidateInitialState(num_ips);
    initialStateValidator.ips <== ips;
    initialStateValidator.geohashes <== geohashes;
    initialStateValidator.last_fingerprint <== last_fingerprint;
    initialStateValidator.yob <== yob;
    initialStateValidator.users_prf_seed <== users_prf_seed;
    initialStateValidator.state_counter <== state_counter;
    initialStateValidator.initial_state_r8x <== initial_state_r8x;
    initialStateValidator.initial_state_r8y <== initial_state_r8y;
    initialStateValidator.initial_state_s <== initial_state_s;
    initialStateValidator.comm_rand <== initial_comm_rand;

    old_state_nullifier <== initialStateValidator.nullifier;

    // Validate new information and produce nullifier
    component serverResponseValidator = ValidateServerResponse();
    serverResponseValidator.new_ip <== new_ip;
    serverResponseValidator.new_geohash <== new_geohash;
    serverResponseValidator.new_rappor_nonce <== new_rappor_nonce;
    serverResponseValidator.new_fingerprint_nonce <== new_fingerprint_nonce;
    serverResponseValidator.server_response_r8x <== new_user_info_r8x;
    serverResponseValidator.server_response_r8y <== new_user_info_r8y;
    serverResponseValidator.server_response_s <== new_user_info_s;
    serverResponseValidator.users_prf_seed <== users_prf_seed;

    server_response_nullifier <== serverResponseValidator.nullifier;
    
    // Geohash distance check. We will check that at a given precision,
    // the geohash of the new IP is neighboring one of the last num_ips
    // signal geohash_offset <== 20000000; // configurable parameter, 20 million like the tests.

    // 15 bits of precision = 3 shared 32-bit characters, aka bounding box ≤ 156km X 156km.
    // var geohash_shared_bits = 15;

    // 20 bits of precision = 4 shared 32-bit characters, aka bounding box ≤ 39.1km X 19.5km.
    var geohash_shared_bits = 20;

    // 25 bits of precision = 5 shared 32-bit characters, aka bounding box ≤ 4.89km X 4.89km.
    // var geohash_shared_bits = 25;

    // Convert new geohash and old geohashes to bits
    signal new_geohash_bits[64] <== Num2Bits(64)(new_geohash);
    signal geohashes_bits[num_ips][64];
    for (var i = 0; i < num_ips; i++) {
        geohashes_bits[i] <== Num2Bits(64)(geohashes[i]);
    }

    // Extract shared bits from new geohash and old geohashes
    signal new_geohash_bits_shared[geohash_shared_bits];
    signal geohashes_bits_shared[num_ips][geohash_shared_bits];

    for (var i = 0; i < geohash_shared_bits; i++) {
        new_geohash_bits_shared[i] <== new_geohash_bits[60 - geohash_shared_bits + i];
    }

    for (var i = 0; i < num_ips; i++) {
        for (var j = 0; j < geohash_shared_bits; j++) {
            geohashes_bits_shared[i][j] <== geohashes_bits[i][60 - geohash_shared_bits + j];
        }
    }

    // Declare all components at the top level
    component bit_equals[num_ips][geohash_shared_bits];
    component all_bits_equal_checks[num_ips];
    signal all_bits_equal[num_ips];
    
    // Initialize bit comparison components
    for (var i = 0; i < num_ips; i++) {
        all_bits_equal_checks[i] = MultiAND(geohash_shared_bits);
        for (var j = 0; j < geohash_shared_bits; j++) {
            bit_equals[i][j] = IsEqual();
            bit_equals[i][j].in[0] <== new_geohash_bits_shared[j];
            bit_equals[i][j].in[1] <== geohashes_bits_shared[i][j];
            all_bits_equal_checks[i].in[j] <== bit_equals[i][j].out;
        }
        all_bits_equal[i] <== all_bits_equal_checks[i].out;
    }

    // Check if any of the prefixes match
    component any_prefix_match = MultiOR(num_ips);
    for (var i = 0; i < num_ips; i++) {
        any_prefix_match.in[i] <== all_bits_equal[i];
    }

    // Compute values for responses
    component is_zero_for_distinct_count[num_ips];
    signal running_sum[num_ips];
    for (var i = 0; i < num_ips; i++) {
        is_zero_for_distinct_count[i] = IsZero();
        is_zero_for_distinct_count[i].in <== ips[i];
        if (i == 0) {
            running_sum[i] <== is_zero_for_distinct_count[i].out;
        } else {
            running_sum[i] <== running_sum[i-1] + is_zero_for_distinct_count[i].out;
        }
    }
    signal distinct_ips_count <== num_ips - running_sum[num_ips - 1];

    signal is_ip_list_empty <== IsEqual()([distinct_ips_count, 0]);
    signal valid_new_geohash <== OR()(any_prefix_match.out, is_ip_list_empty);
    
    valid_new_geohash === 1;

    // Browser fingerprint check
    component fingerprint_similarity_score_calc = HashSimilarityScore(2);
    fingerprint_similarity_score_calc.hash1 <== last_fingerprint;
    fingerprint_similarity_score_calc.hash2 <== new_fingerprint;
    signal fingerprint_similarity <== fingerprint_similarity_score_calc.similarity_score;

    // 90% similarity threshold
    // var fingerprint_similarity_threshold = 450;

    // 80% similarity threshold
    var fingerprint_similarity_threshold = 400;

    // 70% similarity threshold
    // var fingerprint_similarity_threshold = 300;

    component similarity_score_checker = LessThan(10);
    similarity_score_checker.in[0] <== fingerprint_similarity_threshold;
    similarity_score_checker.in[1] <== fingerprint_similarity;
    similarity_score_checker.out === 1;

    // Commitment to the client's fingerprint.
    component fingerprint_commitment_hasher = Poseidon(3);
    fingerprint_commitment_hasher.inputs[0] <== new_fingerprint_nonce;
    fingerprint_commitment_hasher.inputs[1] <== new_fingerprint[0];
    fingerprint_commitment_hasher.inputs[2] <== new_fingerprint[1];
    new_fingerprint_commitment <== fingerprint_commitment_hasher.out;

    // Produce RAPPOR response
    // Set up stuff
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

    // Add responses to bloom filter.
    component add_distinct_ips_to_filter = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_distinct_ips_to_filter.initial_filter <== empty_bloom_filter;
    add_distinct_ips_to_filter.new_value <== distinct_ips_count;
    component add_fingerprint_similarity_to_filter = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_fingerprint_similarity_to_filter.initial_filter <== add_distinct_ips_to_filter.new_filter;
    add_fingerprint_similarity_to_filter.new_value <== fingerprint_similarity;
    component add_geohash_distance_to_filter = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_geohash_distance_to_filter.initial_filter <== add_fingerprint_similarity_to_filter.new_filter;
    // add_geohash_distance_to_filter.new_value <== geohash_offset;
    add_geohash_distance_to_filter.new_value <== geohash_shared_bits;

    component randomize_bloom_filter = IndividualRandomizedResponse(num_bloombits);
    randomize_bloom_filter.prr <== add_geohash_distance_to_filter.new_filter;
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

    // Produce updated state
    // Propose new state
    component updateState = CreateUpdatedState(num_ips);
    updateState.initialState_ips <== ips;
    updateState.initialState_geohashes <== geohashes;
    updateState.yob <== yob;
    updateState.users_prf_seed <== users_prf_seed;
    updateState.state_counter <== state_counter;
    updateState.new_ip <== new_ip;
    updateState.new_geohash <== new_geohash;
    updateState.new_fingerprint <== new_fingerprint;
    updateState.state_comm_randomness <== state_comm_randomness;

    // Output
    new_state_commitment <== updateState.new_state_commitment;
}

// ============== CHAINED HASH FOR LONG INPUTS =================
// Hashes an array using blocks of 15 inputs + previous hash per block
template ChainedPoseidonHash(len) {
    signal input in[len];
    signal output out;

    var num_blocks = (len \ 15) + (len % 15 != 0 ? 1 : 0);
    component block_poseidon[num_blocks];

    // Initialize all Poseidon components
    for (var i = 0; i < num_blocks; i++) {
        block_poseidon[i] = Poseidon(16);  // 15 inputs + 1 previous hash
    }

    // First block: just the first 15 inputs (or fewer if len < 15)
    var first_block_size = len < 15 ? len : 15;
    for (var i = 0; i < first_block_size; i++) {
        block_poseidon[0].inputs[i] <== in[i];
    }
    // Pad first block with zeros if needed
    for (var i = first_block_size; i < 15; i++) {
        block_poseidon[0].inputs[i] <== 0;
    }
    block_poseidon[0].inputs[15] <== 0; // No previous hash for first block

    // Subsequent blocks: 15 inputs + previous hash
    for (var b = 1; b < num_blocks; b++) {
        var start_idx = b * 15;
        var remaining = len - start_idx;
        var block_size = remaining < 15 ? remaining : 15;
        
        // Connect inputs
        for (var i = 0; i < block_size; i++) {
            block_poseidon[b].inputs[i] <== in[start_idx + i];
        }
        // Pad with zeros if needed
        for (var i = block_size; i < 15; i++) {
            block_poseidon[b].inputs[i] <== 0;
        }
        // Connect previous hash
        block_poseidon[b].inputs[15] <== block_poseidon[b-1].out;
    }

    // Final output is the last block's hash
    out <== block_poseidon[num_blocks-1].out;
}

// component main = AttemptStateUpdate(5);
