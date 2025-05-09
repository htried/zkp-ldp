pragma circom 2.2.0;

include "geohash.circom";
include "../circomlib/circuits/gates.circom";

template GeohashTest() {
    signal input lat;    // Latitude (scaled by 1000000)
    signal input lng;    // Longitude (scaled by 1000000)
    
    signal output bits[64];
    signal output chars[12];
    
    component encoder = Geohash();
    encoder.lat <== lat;
    encoder.lng <== lng;
    
    bits <== encoder.bits;
    chars <== encoder.chars;
}

component main {public [lat, lng]} = GeohashTest();