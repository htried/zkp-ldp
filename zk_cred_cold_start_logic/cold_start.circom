include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/gates.circom";
include "circomlib/circuits/poseidon.circom";
include "../self/circuits/circuits/register/register.circom";

template InitializeEmptyState(num_ips) {
    var DG_HASH_ALGO = 256;
    var ECONTENT_HASH_ALGO = 256;
    var signatureAlgorithm = 46;
    var n = 120;
    var k = 35;
    var MAX_ECONTENT_PADDED_LEN = 512;
    var MAX_SIGNED_ATTR_PADDED_LEN = 128;
    var DG1_LEN = 93;
    var MAX_DSC_LENGTH = 1792;
    var nLevels = 21;
    var kLengthFactor = 1;
    var kScaled = k * kLengthFactor;

    signal input fingerprint[2];
    signal input users_prf_seed;
    signal input initial_comm_rand; 

    // Passport inputs
    signal input raw_dsc[MAX_DSC_LENGTH];
    signal input raw_dsc_actual_length;
    signal input dsc_pubKey_offset;
    signal input dsc_pubKey_actual_size;

    signal input dg1[DG1_LEN];
    signal input dg1_hash_offset;
    signal input eContent[MAX_ECONTENT_PADDED_LEN];
    signal input eContent_padded_length;
    signal input signed_attr[MAX_SIGNED_ATTR_PADDED_LEN];
    signal input signed_attr_padded_length;
    signal input signed_attr_econtent_hash_offset;
    signal input pubKey_dsc[kScaled];
    signal input signature_passport[kScaled];

    signal input merkle_root;
    signal input leaf_depth;
    signal input path[nLevels];
    signal input siblings[nLevels];

    signal input csca_tree_leaf;
    
    signal input secret;

    // Commitment to the client's new state which the server signs.
    signal output new_state_commitment;
    // Passport stuff
    signal output passport_nullifier;
    signal output passport_commitment;

    var len = num_ips + num_ips + 2 + 2 + 1 + 1;
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
    state_hasher.inputs[2*num_ips + 2] <== dg1[62]; // bytes for year of birth.
    state_hasher.inputs[2*num_ips + 3] <== dg1[63];
    state_hasher.inputs[2*num_ips + 4] <== users_prf_seed;
    state_hasher.inputs[2*num_ips + 5] <== 0; // the state counter, starts at 0

    component comm_hasher = Poseidon(2);
    comm_hasher.inputs[0] <== initial_comm_rand;
    comm_hasher.inputs[1] <== state_hasher.out;

    new_state_commitment <== comm_hasher.out;

    component verify_registration = REGISTER(DG_HASH_ALGO,
        ECONTENT_HASH_ALGO,
        signatureAlgorithm,
        n,
        k,
        MAX_ECONTENT_PADDED_LEN,
        MAX_SIGNED_ATTR_PADDED_LEN);

    verify_registration.raw_dsc <== raw_dsc;
    verify_registration.raw_dsc_actual_length <== raw_dsc_actual_length;
    verify_registration.dsc_pubKey_offset <== dsc_pubKey_offset;
    verify_registration.dsc_pubKey_actual_size <== dsc_pubKey_actual_size;
    verify_registration.dg1 <== dg1;
    verify_registration.dg1_hash_offset <== dg1_hash_offset;
    verify_registration.eContent <== eContent;
    verify_registration.eContent_padded_length <== eContent_padded_length;
    verify_registration.signed_attr <== signed_attr;
    verify_registration.signed_attr_padded_length <== signed_attr_padded_length;
    verify_registration.signed_attr_econtent_hash_offset <== signed_attr_econtent_hash_offset;
    verify_registration.pubKey_dsc <== pubKey_dsc;
    verify_registration.signature_passport <== signature_passport;
    verify_registration.merkle_root <== merkle_root;
    verify_registration.leaf_depth <== leaf_depth;
    verify_registration.path <== path;
    verify_registration.siblings <== siblings;
    verify_registration.csca_tree_leaf <== csca_tree_leaf;
    verify_registration.secret <== secret;    

    passport_nullifier <== verify_registration.nullifier;
    passport_commitment <== verify_registration.commitment;
}

component main = InitializeEmptyState(5);