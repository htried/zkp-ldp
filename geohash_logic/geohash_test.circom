pragma circom 2.2.0;

include "geohash.circom";
include "../circomlib/circuits/gates.circom";
include "../circomlib/circuits/comparators.circom";

// Generate constraint numbers for the paper.
// circom ./geohash_test.circom --output ./build/ -l circomlib --r1cs --wasm --sym --c

template GeohashTest() {
    signal input geohash1;    // First geohash
    signal input geohash2;    // Second geohash
    
    // Geohash distance check. We will check that at a given precision,
    // the geohash of the new IP is neighboring one of the last num_ips
    // signal geohash_offset <== 20000000; // configurable parameter, 20 million like the tests.

    // 15 bits of precision = 3 shared 32-bit characters, aka bounding box ≤ 156km X 156km.
    // var geohash_shared_bits = 15;

    // 20 bits of precision = 4 shared 32-bit characters, aka bounding box ≤ 39.1km X 19.5km.
    // var geohash_shared_bits = 20;

    // 25 bits of precision = 5 shared 32-bit characters, aka bounding box ≤ 4.89km X 4.89km.
    var geohash_shared_bits = 25;

    // Convert new geohash and old geohashes to bits
    signal geohash1_bits[64] <== Num2Bits(64)(geohash1);
    signal geohash2_bits[64] <== Num2Bits(64)(geohash2);

    // Extract shared bits from new geohash and old geohashes
    signal geohash1_bits_shared[geohash_shared_bits];
    signal geohash2_bits_shared[geohash_shared_bits];

    for (var i = 0; i < geohash_shared_bits; i++) {
        geohash1_bits_shared[i] <== geohash1_bits[60 - geohash_shared_bits + i];
        geohash2_bits_shared[i] <== geohash2_bits[60 - geohash_shared_bits + i];
    }

    // Declare all components at the top level
    component bit_equals[geohash_shared_bits];
    component all_bits_equal_check;
    signal all_bits_equal;
    
    // Initialize bit comparison components
    all_bits_equal_check = MultiAND(geohash_shared_bits);
    for (var j = 0; j < geohash_shared_bits; j++) {
        bit_equals[j] = IsEqual();
        bit_equals[j].in[0] <== geohash1_bits_shared[j];
        bit_equals[j].in[1] <== geohash2_bits_shared[j];
        all_bits_equal_check.in[j] <== bit_equals[j].out;
    }
    all_bits_equal <== all_bits_equal_check.out;
}

component main {public [geohash1, geohash2]} = GeohashTest();