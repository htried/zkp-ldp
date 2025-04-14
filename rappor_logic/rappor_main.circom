pragma circom 2.2.0;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/gates.circom";
include "circomlib/circuits/mux1.circom";

// Simple implementation of RAPPOR randomized response in circom.
// Bloom filter sizes and parameters are fixed, though they should be configurable,
// randomness is a public input like in a "randomness beacon" environment.
// Also lets us do some dependency injection type things.
// All probabilities are numbers between 0 and 255 (and represent the probability
// (n+1)/256)
// Number of bloom bits also set to powers of 2 to efficiently take moduli in circuit.

// Handwritten multi-or implementation since it doesn't seem to exist. Based on MultiAND from gates.circom
template MultiOR(n) {
    signal input in[n];
    signal output out;
    component or1;
    component or2;
    component ors[2];
    if (n==1) {
        out <== in[0];
    } else if (n==2) {
        or1 = OR();
        or1.a <== in[0];
        or1.b <== in[1];
        out <== or1.out;
    } else {
        or2 = OR();
        var n1 = n\2;
        var n2 = n-n\2;
        ors[0] = MultiOR(n1);
        ors[1] = MultiOR(n2);
        var i;
        for (i=0; i<n1; i++) ors[0].in[i] <== in[i];
        for (i=0; i<n2; i++) ors[1].in[i] <== in[n1+i];
        or2.a <== ors[0].out;
        or2.b <== ors[1].out;
        out <== or2.out;
    }
}

template AddToBloomFilter() {
    var num_hashes = 2;
    var num_bloombits = 16;
    // This should be the log of bloom bits (self explanatory)
    // Not a nice way to take log in circom scripts (or have constants for
    // the whole program)
    var log_bloombits = 4;

    signal input initial_filter[num_bloombits];
    signal input new_value;
    signal output new_filter[num_bloombits];

    // Get the bloom bits to set
    component hasher = Poseidon(1);
    hasher.inputs[0] <== new_value;

    component hashToBits = Num2Bits(255);
    hashToBits.in <== hasher.out;

    // As in the RAPPOR implementation, we implement the separate 'hashes' for the 
    // bloom filter by taking separate substrings of the hash of the value and using them
    // to produce indices.
    component bloomFilterIndicesToSet[num_hashes];
    // Turn them into integers
    for(var i = 0; i < num_hashes; i++) {
        bloomFilterIndicesToSet[i] = Bits2Num(log_bloombits);
        for(var j = 0; j < 4; j++) { 
            bloomFilterIndicesToSet[i].in[j] <== hashToBits.out[i*log_bloombits + j];
        }
    }

    // Block of muxes to set each relevant bit.
    component bloomFilterMuxes[num_bloombits];
    component bloomFilterMuxEqChecks[num_bloombits][num_hashes];
    component bloomFilterMuxMultiOrs[num_bloombits];
    for(var i = 0; i < num_bloombits; i++) {
        bloomFilterMuxMultiOrs[i] = MultiOR(num_hashes);
        for(var j = 0; j < num_hashes; j++) {
            bloomFilterMuxEqChecks[i][j] = IsEqual();
            bloomFilterMuxEqChecks[i][j].in[0] <== i;
            bloomFilterMuxEqChecks[i][j].in[1] <== bloomFilterIndicesToSet[j].out;
            bloomFilterMuxMultiOrs[i].in[j] <== bloomFilterMuxEqChecks[i][j].out;
        }
        bloomFilterMuxes[i] = Mux1();
        bloomFilterMuxes[i].s <== bloomFilterMuxMultiOrs[i].out;
        bloomFilterMuxes[i].c[0] <== initial_filter[i];
        bloomFilterMuxes[i].c[1] <== 1;
    }

    for(var i = 0; i < num_bloombits; i++) {
        new_filter[i] <== bloomFilterMuxes[i].out;
    }
}

// In a full implementation, the state would need to contain the PRR 
// (maybe). Our use case might not need the PRR step, and may also be the
// "data changes slightly" case where you need to think more about security.
template PermanentRandomizedResponse() {
    var prob_f = 127;
    var num_bloombits = 16;
    // Bits encoded in each probability
    var probability_bits = 8;

    signal input bloom_filter[num_bloombits];
    // f randomness will have to increase if num probability bits or 
    // num bloombits increases. 
    // Interesting google's rappor reference implementation only uses 7 bits of entropy here.
    signal input f_randomness;

    signal output prr[num_bloombits]; 

    // Convert f randomness into blocks of 8 bits.
    component fToBits = Num2Bits(250);
    fToBits.in <== f_randomness;

    component f_chunks[num_bloombits];
    for (var i = 0; i < num_bloombits; i++) {
        f_chunks[i] = Bits2Num(probability_bits);
        for (var j = 0; j < probability_bits; j++) {
            f_chunks[i].in[j] <== fToBits.out[i*probability_bits + j];
        }
    }

    // Do comparisons with prob_f for each ones, and set the bits of the output based
    // on muxes
    component probability_comparisons[num_bloombits];
    signal f_mask[num_bloombits];
    for (var i = 0; i < num_bloombits; i++) {
        probability_comparisons[i] = LessThan(probability_bits);
        probability_comparisons[i].in[0] <== f_chunks[i].out;
        probability_comparisons[i].in[1] <== prob_f;

        f_mask[i] <== probability_comparisons[i].out;
    }

    signal uniform_mask[num_bloombits];
    for(var i = 0; i < num_bloombits; i++) {
        uniform_mask[i] <== fToBits.out[i + num_bloombits * probability_bits];
    }

    // Compute: prr = (bits & ~f_mask) | (uniform & f_mask)
    component not_f_mask[num_bloombits];
    component bits_and_not_f_mask[num_bloombits];
    component uniform_and_f_mask[num_bloombits];
    component ors_for_prr[num_bloombits];
    for(var i = 0; i < num_bloombits; i++) {
        not_f_mask[i] = NOT();
        not_f_mask[i].in <== f_mask[i];

        bits_and_not_f_mask[i] = AND();
        bits_and_not_f_mask[i].a <== bloom_filter[i];
        bits_and_not_f_mask[i].b <== not_f_mask[i].out;

        uniform_and_f_mask[i] = AND();
        uniform_and_f_mask[i].a <== uniform_mask[i];
        uniform_and_f_mask[i].b <== f_mask[i];

        ors_for_prr[i] = OR();
        ors_for_prr[i].a <== bits_and_not_f_mask[i].out;
        ors_for_prr[i].b <== uniform_and_f_mask[i].out;
        
        prr[i] <== ors_for_prr[i].out;
    }
}

template IndividualRandomizedResponse() {
    var num_bloombits = 16;
    var prob_p = 127;
    var prob_q = 191;
    var probability_bits = 8;

    signal input prr[num_bloombits];
    // f randomness will have to increase if num probability bits or 
    // num bloombits increases.
    signal input p_randomness;
    signal input q_randomness;

    signal output irr[num_bloombits];

    // Convert p randomness, q randomness into blocks of 8 bits.
    component pToBits = Num2Bits(250);
    pToBits.in <== p_randomness;
    component qToBits = Num2Bits(250);
    qToBits.in <== q_randomness;

    component p_chunks[num_bloombits];
    component q_chunks[num_bloombits];
    for (var i = 0; i < num_bloombits; i++) {
        p_chunks[i] = Bits2Num(probability_bits);
        q_chunks[i] = Bits2Num(probability_bits);
        for (var j = 0; j < probability_bits; j++) {
            p_chunks[i].in[j] <== pToBits.out[i*probability_bits + j];
            q_chunks[i].in[j] <== qToBits.out[i*probability_bits + j];
        }
    }

    // Do comparisons with prob_p, prob_q for each of the blocks
    component p_probability_comparisons[num_bloombits];
    component q_probability_comparisons[num_bloombits];
    signal p_bits[num_bloombits];
    signal q_bits[num_bloombits];
    for (var i = 0; i < num_bloombits; i++) {
        p_probability_comparisons[i] = LessThan(probability_bits);
        p_probability_comparisons[i].in[0] <== p_chunks[i].out;
        p_probability_comparisons[i].in[1] <== prob_p;
        p_bits[i] <== p_probability_comparisons[i].out;

        q_probability_comparisons[i] = LessThan(probability_bits);
        q_probability_comparisons[i].in[0] <== q_chunks[i].out;
        q_probability_comparisons[i].in[1] <== prob_p;
        q_bits[i] <== q_probability_comparisons[i].out;
    }

    // Compute (p_bits & ~prr) | (q_bits & prr)
    component not_prr[num_bloombits];
    component p_bits_and_not_prr[num_bloombits];
    component q_bits_and_prr[num_bloombits];
    component ors_for_irr[num_bloombits];
    for(var i = 0; i < num_bloombits; i++) {
        not_prr[i] = NOT();
        not_prr[i].in <== prr[i];

        p_bits_and_not_prr[i] = AND();
        p_bits_and_not_prr[i].a <== p_bits[i];
        p_bits_and_not_prr[i].b <== not_prr[i].out;

        q_bits_and_prr[i] = AND();
        q_bits_and_prr[i].a <== q_bits[i];
        q_bits_and_prr[i].b <== prr[i];

        ors_for_irr[i] = OR();
        ors_for_irr[i].a <== p_bits_and_not_prr[i].out;
        ors_for_irr[i].b <== q_bits_and_prr[i].out;

        irr[i] <== ors_for_irr[i].out;
    }
}

template RapporMain() {
    var num_bloombits = 16;

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
    component add_to_bloom = AddToBloomFilter();
    add_to_bloom.initial_filter <== old_bloom_to_bits.out;
    add_to_bloom.new_value <== new_value;

    // Generate a PRR for the new bloom filter
    component generate_prr = PermanentRandomizedResponse();
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
    component generate_irr = IndividualRandomizedResponse();
    generate_irr.prr <== prr_for_irr.out;
    generate_irr.p_randomness <== p_randomness;
    generate_irr.q_randomness <== q_randomness;

    // Convert the new IRR to a number to return (more efficient to pass around felts)
    component irrToNum = Bits2Num(16);
    irrToNum.in <== generate_irr.irr;

    rappor_response <== irrToNum.out;
}

// Implementing this in the "randomness beacon" model, where a server would verify
// that these inputs are actually a randomness beacon output for the relevant time period.
// May need to increase amount of randomness (or use poseidon as XOF) if num_bloombits gets larger than
// the entropy in 1 field element.
component main {public [p_randomness, q_randomness, f_randomness]} = RapporMain();