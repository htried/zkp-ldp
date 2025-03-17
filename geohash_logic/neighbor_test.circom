pragma circom 2.2.0;

include "geohash.circom";
include "circomlib/circuits/gates.circom";

template NeighborTest() {
    signal input lat;    // Latitude (scaled by 1000)
    signal input lng;    // Longitude (scaled by 1000)
    signal input bits;   // Number of bits to use for the hash
    signal input direction; // Direction (0-7)
    
    signal output hash[64];     // Original geohash bits
    signal output neighbor[64]; // Neighbor geohash bits
    
    // First encode the coordinates to a geohash
    component encoder = EncodeIntWithPrecisionSimple(64);
    encoder.lat <== lat;
    encoder.lng <== lng;
    encoder.bits <== bits;
    
    // Copy the hash to the output
    for (var i = 0; i < 64; i++) {
        hash[i] <== encoder.hash[i];
    }
    
    // Now compute the neighbor
    component neighborCalc = SimpleNeighbor();
    
    // Connect the hash bits
    for (var i = 0; i < 64; i++) {
        neighborCalc.hash[i] <== hash[i];
    }
    
    // Connect the direction
    neighborCalc.direction <== direction;
    
    // Copy the neighbor hash to the output
    for (var i = 0; i < 64; i++) {
        neighbor[i] <== neighborCalc.neighbor[i];
    }
}

component main {public [lat, lng, direction]} = NeighborTest();