pragma circom 2.2.0;

include "geohash.circom";
include "../circomlib/circuits/gates.circom";

template NeighborTest() {
    signal input lat;         // Latitude (scaled by 1000000)
    signal input lng;         // Longitude (scaled by 1000000)
    signal input direction;   // Direction (0-7)
    signal input offset;      // Offset in degrees * 1e6
    
    signal output hash[64];     // Original geohash bits
    signal output chars[12];    // Original base32 chars
    signal output neighbor[64]; // Neighbor geohash bits
    signal output neighborChars[12]; // Neighbor base32 chars
    
    // First encode the coordinates
    component encoder = Geohash(32);
    encoder.lat <== lat;
    encoder.lng <== lng;
    
    // Copy original outputs
    hash <== encoder.bits;
    chars <== encoder.chars;
    
    // Compute neighbor with configurable offset
    component neighborCalc = Neighbor();
    neighborCalc.hash <== hash;
    neighborCalc.direction <== direction;
    neighborCalc.offset <== offset;
    
    // Copy neighbor outputs
    neighbor <== neighborCalc.neighbor;
    neighborChars <== neighborCalc.chars;
}

component main {public [lat, lng, direction, offset]} = NeighborTest();