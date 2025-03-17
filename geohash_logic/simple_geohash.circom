pragma circom 2.2.0;

include "circuits/bitify.circom";
include "circuits/comparators.circom";

template SimpleGeohash() {
    signal input lat;  // Latitude as integer (0-90000)
    signal input lng;  // Longitude as integer (0-360000)
    signal output lat_bits[32];
    signal output lng_bits[32];
    signal output interleaved[64];
    
    // Debug signals
    signal output lat_in_range;
    signal output lng_in_range;
    
    // Check input ranges
    component latCheck = LessThan(32);
    latCheck.in[0] <== lat;
    latCheck.in[1] <== 90001;
    lat_in_range <== latCheck.out;
    
    component lngCheck = LessThan(32);
    lngCheck.in[0] <== lng;
    lngCheck.in[1] <== 360001;
    lng_in_range <== lngCheck.out;
    
    // Convert to bits
    component latBits = Num2Bits(32);
    latBits.in <== lat;
    lat_bits <== latBits.out;
    
    component lngBits = Num2Bits(32);
    lngBits.in <== lng;
    lng_bits <== lngBits.out;
    
    // Interleave
    for (var i = 0; i < 32; i++) {
        interleaved[2*i] <== lat_bits[i];
        interleaved[2*i+1] <== lng_bits[i];
    }
} 

// A very simple geohash encoder
component main {public [lat, lng]} = SimpleGeohash();