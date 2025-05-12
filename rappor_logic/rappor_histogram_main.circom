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

    signal old_bloom_state <== 0;
    
    signal input p_randomness;
    signal input q_randomness;

    signal input new_value;

    signal output rappor_response;

    // Convert old bloom filter to a representation that's easy to work with.
    component old_bloom_to_bits = Num2Bits(num_bloombits);
    old_bloom_to_bits.in <== old_bloom_state;

    // Add new value to bloom filter.
    component add_to_bloom = AddToBloomFilter(num_hashes, num_bloombits, log_bloombits);
    add_to_bloom.initial_filter <== old_bloom_to_bits.out;
    add_to_bloom.new_value <== new_value;

    // Generate the IRR based on the new or old PRR
    component generate_irr = IndividualRandomizedResponse(num_bloombits);
    generate_irr.prr <== add_to_bloom.new_filter;
    generate_irr.p_randomness <== p_randomness;
    generate_irr.q_randomness <== q_randomness;

    // Convert the new IRR to a number to return (more efficient to pass around felts)
    component irrToNum = Bits2Num(16);
    irrToNum.in <== generate_irr.irr;

    rappor_response <== irrToNum.out;
}

component main {public [p_randomness, q_randomness]} = RapporMain();