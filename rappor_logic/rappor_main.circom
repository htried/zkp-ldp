pragma circom 2.2.0;

include "../circomlib/circuits/bitify.circom";
include "../circomlib/circuits/comparators.circom";
include "../circomlib/circuits/poseidon.circom";
include "../circomlib/circuits/gates.circom";
include "../circomlib/circuits/mux1.circom";
include "rappor.circom";

template RapporMain() {
    var num_hashes = 2;
    var num_bloombits = 16;
    var log_bloombits = 4;

    signal input f_randomness;
    signal input p_randomness;
    signal input q_randomness;
    signal input old_bloom_state;
    // Maybe somehow output commitment to new RAPPOR state and new bloom filter state, 
    // but this state management is related to the credential.
    signal input old_prr_state;
    signal input new_value;

    // Control signal for whether we produce a new PRR or not.
    signal input add_new_value;
    add_new_value * (add_new_value - 1) === 0;

    signal output rappor_response;

    // Convert old bloom filter to a representation that's easy to work with.
    component old_bloom_to_bits = Num2Bits(num_bloombits);
    old_bloom_to_bits.in <== old_bloom_state;

    // Add new value to bloom filter.
    component add_to_bloom = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_to_bloom.initial_filter <== old_bloom_to_bits.out;
    add_to_bloom.new_value <== new_value;

    // Generate a PRR for the new bloom filter
    component generate_prr = PermanentRandomizedResponse(num_bloombits);
    generate_prr.bloom_filter <== add_to_bloom.new_filter;
    generate_prr.f_randomness <== f_randomness;

    // TODO: Add a mux for switching between the old PRR (if not changing bloom state)
    // and the newly generated PRR
    component old_prr_to_bits = Num2Bits(num_bloombits);
    old_prr_to_bits.in <== old_prr_state;
    
    component prr_for_irr = MultiMux1(num_bloombits);
    prr_for_irr.s <== add_new_value;
    for (var i = 0; i < num_bloombits; i++) {
        prr_for_irr.c[i][0] <== old_prr_to_bits.out[i];
        prr_for_irr.c[i][1] <== generate_prr.prr[i];
    }

    // Generate the IRR based on the new or old PRR
    component generate_irr = IndividualRandomizedResponse(num_bloombits);
    generate_irr.prr <== prr_for_irr.out;
    generate_irr.p_randomness <== p_randomness;
    generate_irr.q_randomness <== q_randomness;

    // Convert the new IRR to a number to return (more efficient to pass around felts)
    component irrToNum = Bits2Num(16);
    irrToNum.in <== generate_irr.irr;

    rappor_response <== irrToNum.out;
}

// For dependency injection reasons, the randomnesses are public inputs here.
component main {public [p_randomness, q_randomness, f_randomness]} = RapporMain();