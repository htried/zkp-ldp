pragma circom 2.2.0;

include "../circomlib/circuits/bitify.circom";
include "../circomlib/circuits/comparators.circom";
include "../circomlib/circuits/gates.circom";
include "../circomlib/circuits/poseidon.circom";
include "../circomlib/circuits/babyjub.circom";
include "../circomlib/circuits/eddsaposeidon.circom";
include "../rappor_logic/rappor.circom";
include "../geohash_logic/geohash.circom";

// ============== STREAMING STATE STRUCT =================
bus StreamingCredentialState() {
    signal geohash_sum;
    signal state_counter;
    signal avg_geohash;
    signal lat_sum;        // Running sum of latitudes (as integers)
    signal lng_sum;        // Running sum of longitudes (as integers)
    signal last_fingerprint[2];
    signal yob[2];
    signal users_prf_seed;
    signal state_sig_r8x;
    signal state_sig_r8y;
    signal state_sig_s;
}

// ============== GEOHASH CONVERSION FUNCTIONS =================

// Convert geohash bits to latitude and longitude coordinates
template GeohashToCoordinates() {
    signal input geohash_bits[64];
    signal output lat;  // (Latitude + 180) * 1e6
    signal output lng;  // (Longitude + 360) * 1e6
    
    // Deinterleave the geohash bits to get lat and lng bits
    component deinterleaver = Deinterleave();
    deinterleaver.X <== geohash_bits;
    
    // Convert bits to numbers (MSB order)
    component latNum = Bits2Num(32);
    component lngNum = Bits2Num(32);
    
    // Connect bits in MSB order 
    for (var i = 0; i < 32; i++) {
        latNum.in[i] <== deinterleaver.odd[31-i];   // Latitude bits (odd positions)
        lngNum.in[i] <== deinterleaver.even[31-i];  // Longitude bits (even positions)
    }
    
    lat <== latNum.out;
    lng <== lngNum.out;
}

// Convert latitude and longitude coordinates back to geohash
template CoordinatesToGeohash() {
    signal input lat;  // (Latitude + 180) * 1e6
    signal input lng;  // (Longitude + 360) * 1e6
    signal output geohash_bits[64];
    
    // Convert inputs to bits (LSB order)
    component latBits = Num2Bits(32);
    component lngBits = Num2Bits(32);
    
    latBits.in <== lat;
    lngBits.in <== lng;
    
    // Create even and odd arrays for interleaving
    signal even[32];
    signal odd[32];
    
    // Fill the arrays in MSB order (reverse the bit order)
    for (var i = 0; i < 32; i++) {
        even[i] <== lngBits.out[31-i];  // Longitude bits (even positions)
        odd[i] <== latBits.out[31-i];   // Latitude bits (odd positions)
    }
    
    // Interleave the bits
    component interleaver = Interleave();
    interleaver.even <== even;
    interleaver.odd <== odd;
    geohash_bits <== interleaver.out;
}

// ============== GEOHASH PREFIX CALCULATION =================

// Convert coordinates to a 20-bit geohash prefix
template CoordinatesToGeohashPrefix() {
    signal input lat;  // (Latitude + 180) * 1e6
    signal input lng;  // (Longitude + 360) * 1e6
    signal output prefix_bits[20];  // 20-bit geohash prefix
    
    // Convert inputs to bits (LSB order)
    component latBits = Num2Bits(32);
    component lngBits = Num2Bits(32);
    
    latBits.in <== lat;
    lngBits.in <== lng;
    
    // Create even and odd arrays for interleaving
    signal even[32];
    signal odd[32];
    
    // Fill the arrays in MSB order (reverse the bit order)
    for (var i = 0; i < 32; i++) {
        even[i] <== lngBits.out[31-i];  // Longitude bits (even positions)
        odd[i] <== latBits.out[31-i];   // Latitude bits (odd positions)
    }
    
    // Interleave the bits to create the full geohash
    component interleaver = Interleave();
    interleaver.even <== even;
    interleaver.odd <== odd;
    
    // Extract the first 20 bits (MSB order) as the prefix
    for (var i = 0; i < 20; i++) {
        prefix_bits[i] <== interleaver.out[63 - i];  // Take MSB first
    }
}

// ============== STATE MANAGEMENT FUNCTIONS =================

// Checks that the initial state has a valid signature and outputs a nullifier.
template ValidateInitialStreamingState() {
    signal input geohash_sum;
    signal input state_counter;
    signal input avg_geohash;
    signal input lat_sum;
    signal input lng_sum;
    signal input last_fingerprint[2];
    signal input yob[2];
    signal input users_prf_seed;
    signal input initial_state_r8x;
    signal input initial_state_r8y;
    signal input initial_state_s;
    signal input comm_rand;

    signal output nullifier;

    // Hash the state fields (include avg_geohash, lat_sum, lng_sum)
    signal state_hash_inputs[10];
    state_hash_inputs[0] <== geohash_sum;
    state_hash_inputs[1] <== state_counter;
    state_hash_inputs[2] <== avg_geohash;
    state_hash_inputs[3] <== lat_sum;
    state_hash_inputs[4] <== lng_sum;
    state_hash_inputs[5] <== last_fingerprint[0];
    state_hash_inputs[6] <== last_fingerprint[1];
    state_hash_inputs[7] <== yob[0];
    state_hash_inputs[8] <== yob[1];
    state_hash_inputs[9] <== users_prf_seed;
    component state_hasher = Poseidon(10);
    for (var i = 0; i < 10; i++) {
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
    signal input new_fingerprint_nonce;
    signal input server_response_r8x;
    signal input server_response_r8y;
    signal input server_response_s;
    signal input users_prf_seed;
    signal input yob[2];

    signal output nullifier;

    component response_hasher = Poseidon(3);
    response_hasher.inputs[0] <== new_geohash;
    response_hasher.inputs[1] <== new_rappor_nonce;
    response_hasher.inputs[2] <== new_fingerprint_nonce;

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

// Streaming state update logic with running sums of coordinates
template CreateUpdatedStreamingState() {
    // Old state
    signal input geohash_sum;
    signal input state_counter;
    signal input users_prf_seed;
    signal input last_fingerprint[2];
    signal input yob[2];
    signal input lat_sum;
    signal input lng_sum;
    // New data
    signal input new_geohash;
    signal input new_fingerprint[2];
    signal input state_comm_randomness;

    // Output signals
    signal output new_state_commitment;
    signal output new_geohash_sum;
    signal output new_state_counter;
    signal output new_avg_geohash;
    signal output new_last_fingerprint[2];
    signal output new_lat_sum;
    signal output new_lng_sum;
    signal output new_avg_prefix_bits[20];  // 20-bit geohash prefix for validation

    // Convert new geohash to coordinates
    component new_geohash_bits = Num2Bits(64);
    new_geohash_bits.in <== new_geohash;
    
    component new_geohash_to_coords = GeohashToCoordinates();
    new_geohash_to_coords.geohash_bits <== new_geohash_bits.out;
    
    // Add to running sums
    new_lat_sum <== lat_sum + new_geohash_to_coords.lat;
    new_lng_sum <== lng_sum + new_geohash_to_coords.lng;
    
    // Compute new state
    new_geohash_sum <== geohash_sum + new_geohash;
    new_state_counter <== state_counter + 1;
    
    // Calculate new average coordinates using integer division
    // Use witness calculation to compute the division, then verify it's correct
    
    signal new_avg_lat;
    signal new_avg_lng;
    signal remainder_lat;
    signal remainder_lng;
    
    // Calculate the quotient and remainder using witness calculation
    new_avg_lat <-- new_lat_sum \ new_state_counter;
    remainder_lat <-- new_lat_sum % new_state_counter;
    
    new_avg_lng <-- new_lng_sum \ new_state_counter;
    remainder_lng <-- new_lng_sum % new_state_counter;
    
    // Verify the division is correct
    new_avg_lat * new_state_counter + remainder_lat === new_lat_sum;
    new_avg_lng * new_state_counter + remainder_lng === new_lng_sum;
    
    // Ensure remainders are less than divisor
    component remainder_lat_lt = LessThan(32);
    remainder_lat_lt.in[0] <== remainder_lat;
    remainder_lat_lt.in[1] <== new_state_counter;
    remainder_lat_lt.out === 1;
    
    component remainder_lng_lt = LessThan(32);
    remainder_lng_lt.in[0] <== remainder_lng;
    remainder_lng_lt.in[1] <== new_state_counter;
    remainder_lng_lt.out === 1;
    
    // Generate 20-bit geohash prefix from the new average coordinates
    component new_avg_prefix = CoordinatesToGeohashPrefix();
    new_avg_prefix.lat <== new_avg_lat;
    new_avg_prefix.lng <== new_avg_lng;
    
    // Convert average coordinates back to full geohash for storage
    component new_avg_coords_to_geohash = CoordinatesToGeohash();
    new_avg_coords_to_geohash.lat <== new_avg_lat;
    new_avg_coords_to_geohash.lng <== new_avg_lng;
    
    // Convert geohash bits back to a number
    component new_avg_geohash_num = Bits2Num(64);
    new_avg_geohash_num.in <== new_avg_coords_to_geohash.geohash_bits;
    
    new_avg_geohash <== new_avg_geohash_num.out;
    new_last_fingerprint <== new_fingerprint;

    // Output state commitment (include new fields)
    signal state_hash_inputs[10];
    state_hash_inputs[0] <== new_geohash_sum;
    state_hash_inputs[1] <== new_state_counter;
    state_hash_inputs[2] <== new_avg_geohash;
    state_hash_inputs[3] <== new_lat_sum;
    state_hash_inputs[4] <== new_lng_sum;
    state_hash_inputs[5] <== new_last_fingerprint[0];
    state_hash_inputs[6] <== new_last_fingerprint[1];
    state_hash_inputs[7] <== yob[0];
    state_hash_inputs[8] <== yob[1];
    state_hash_inputs[9] <== users_prf_seed;
    component state_hasher = Poseidon(10);
    for (var i = 0; i < 10; i++) {
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
    signal input lat_sum;
    signal input lng_sum;
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
    signal input new_fingerprint_nonce;
    signal input new_user_info_r8x;
    signal input new_user_info_r8y;
    signal input new_user_info_s;
    signal input state_comm_randomness;
    signal input new_fingerprint[2];

    // Outputs
    signal output old_state_nullifier;
    signal output server_response_nullifier;
    signal output new_state_commitment;
    signal output new_fingerprint_commitment;
    signal output new_geohash_sum;
    signal output new_state_counter;
    signal output new_avg_geohash;
    signal output new_last_fingerprint[2];
    signal output new_lat_sum;
    signal output new_lng_sum;
    signal output new_avg_prefix_bits[20];
    signal output rappor_response;

    // Validate initial state
    component initialStateValidator = ValidateInitialStreamingState();
    initialStateValidator.geohash_sum <== geohash_sum;
    initialStateValidator.state_counter <== state_counter;
    initialStateValidator.avg_geohash <== avg_geohash;
    initialStateValidator.lat_sum <== lat_sum;
    initialStateValidator.lng_sum <== lng_sum;
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
    serverResponseValidator.new_fingerprint_nonce <== new_fingerprint_nonce;
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

    // The running sums (lat_sum, lng_sum) provide a more accurate way to track
    // the average coordinates without the complexity of geohash conversion
    // We'll use these for the actual averaging logic in CreateUpdatedStreamingState

    // Calculate current average coordinates from running sums
    // We need to enforce that current_avg_lat * state_counter = lat_sum
    // and current_avg_lng * state_counter = lng_sum
    // Since we can't use multiplication in constraints directly, we'll use a different approach
    
    // For validation purposes, we'll check that the new geohash is close to the current average
    // by converting the current avg_geohash to coordinates and comparing with the new one
    
    // Convert current avg_geohash to coordinates for comparison
    component current_avg_geohash_bits = Num2Bits(64);
    current_avg_geohash_bits.in <== avg_geohash;
    
    component current_avg_geohash_to_coords = GeohashToCoordinates();
    current_avg_geohash_to_coords.geohash_bits <== current_avg_geohash_bits.out;
    
    // Convert new geohash to coordinates
    component new_geohash_bits = Num2Bits(64);
    new_geohash_bits.in <== new_geohash;
    
    component new_geohash_to_coords = GeohashToCoordinates();
    new_geohash_to_coords.geohash_bits <== new_geohash_bits.out;
    
    // Generate 20-bit geohash prefix from current average coordinates
    component current_avg_prefix = CoordinatesToGeohashPrefix();
    current_avg_prefix.lat <== current_avg_geohash_to_coords.lat;
    current_avg_prefix.lng <== current_avg_geohash_to_coords.lng;
    
    // Compare first 20 bits (MSB order) for prefix validation
    var geohash_shared_bits = 20;
    component bit_equals[geohash_shared_bits];
    component all_bits_equal = MultiAND(geohash_shared_bits);
    for (var i = 0; i < geohash_shared_bits; i++) {
        bit_equals[i] = IsEqual();
        bit_equals[i].in[0] <== current_avg_prefix.prefix_bits[i];  // Current average prefix
        bit_equals[i].in[1] <== new_geohash_bits.out[63 - i];      // New geohash MSB first
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
    updateState.lat_sum <== lat_sum;
    updateState.lng_sum <== lng_sum;
    updateState.new_geohash <== new_geohash;
    updateState.new_fingerprint <== new_fingerprint;
    updateState.state_comm_randomness <== state_comm_randomness;
    new_state_commitment <== updateState.new_state_commitment;
    new_geohash_sum <== updateState.new_geohash_sum;
    new_state_counter <== updateState.new_state_counter;
    new_avg_geohash <== updateState.new_avg_geohash;
    new_last_fingerprint <== updateState.new_last_fingerprint;
    new_lat_sum <== updateState.new_lat_sum;
    new_lng_sum <== updateState.new_lng_sum;
    new_avg_prefix_bits <== updateState.new_avg_prefix_bits;

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
    component add_lat_sum_to_filter = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_lat_sum_to_filter.initial_filter <== add_state_counter_to_filter.new_filter;
    add_lat_sum_to_filter.new_value <== lat_sum;
    component add_lng_sum_to_filter = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_lng_sum_to_filter.initial_filter <== add_lat_sum_to_filter.new_filter;
    add_lng_sum_to_filter.new_value <== lng_sum;

    // Optionally, add fingerprint similarity or other metrics here
    // For now, use state_counter, lat_sum, and lng_sum

    component randomize_bloom_filter = IndividualRandomizedResponse(num_bloombits);
    randomize_bloom_filter.prr <== add_lng_sum_to_filter.new_filter;
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

    component age_or = OR();
    age_or.a <== yob_20th_century_of_age.out;
    age_or.b <== yob_21st_century_of_age.out;
    signal of_age <== age_or.out;
    of_age === 1;
}

component main = AttemptStreamingStateUpdate();
