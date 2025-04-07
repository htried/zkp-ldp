pragma circom 2.2.0;

include "circuits/bitify.circom";
include "circuits/comparators.circom";
include "circuits/gates.circom";

// ---- Basic Bit Operations ----

// Interleave bits using spread and combine
template Interleave() {
    signal input even[32];
    signal input odd[32];
    signal output out[64];
    
    // Direct interleaving with single assignments
    for (var i = 0; i < 32; i++) {
        // Each bit is assigned exactly once
        out[2*i] <== even[i];      // Even bits
        out[2*i + 1] <== odd[i];   // Odd bits
    }
}

// Deinterleave using squash operations
template Deinterleave() {
    signal input X[64];
    signal output even[32];
    signal output odd[32];
    
    // Extract even and odd bits directly
    for (var i = 0; i < 32; i++) {
        even[i] <== X[2*i];      // Take bits 0, 2, 4, ...
        odd[i] <== X[2*i + 1];   // Take bits 1, 3, 5, ...
    }
}

// ---- Main Templates ----

template Geohash(precision) {
    signal input lat;    // (Latitude + 90) * 1e6
    signal input lng;    // (Longitude + 180) * 1e6
    signal output bits[64];
    signal output chars[12];
    
    // Convert inputs to bits (LSB order)
    component latBits = Num2Bits(32);
    component lngBits = Num2Bits(32);
    
    latBits.in <== lat;
    lngBits.in <== lng;
    
    
    // Interleave bits in MSB order (reverse the bit order before interleaving)
    for (var i = 0; i < 32; i++) {
        bits[2*i] <== lngBits.out[31-i];     // Even positions get longitude bits, MSB first
        bits[2*i + 1] <== latBits.out[31-i]; // Odd positions get latitude bits, MSB first
    }
    
    // Zero out remaining bits
    for (var i = 64; i < 64; i++) {
        bits[i] <== 0;
    }
    
    // Convert to base32 chars
    for (var i = 0; i < 12; i++) {
        chars[i] <== 
            bits[i*5] * 16 +
            bits[i*5 + 1] * 8 +
            bits[i*5 + 2] * 4 +
            bits[i*5 + 3] * 2 +
            bits[i*5 + 4];
    }
}

template Neighbor() {
    signal input hash[64];  // Input geohash bits
    signal input direction; // Direction (0-7): N, NE, E, SE, S, SW, W, NW
    signal output neighbor[64]; // Output neighbor geohash bits
    signal output chars[12];    // Base32 character indices
    
    // Direction components
    component isDir[8];
    for (var d = 0; d < 8; d++) {
        isDir[d] = IsEqual();
        isDir[d].in[0] <== direction;
        isDir[d].in[1] <== d;
    }
    
    // Deinterleave the hash
    component deinterleaver = Deinterleave();
    deinterleaver.X <== hash;
    
    // Convert deinterleaved bits to numbers
    component latNum = Bits2Num(32);
    component lngNum = Bits2Num(32);
    
    // Connect bits in MSB order 
    for (var i = 0; i < 32; i++) {
        latNum.in[i] <== deinterleaver.odd[31-i];   // Latitude bits (odd positions)
        lngNum.in[i] <== deinterleaver.even[31-i];  // Longitude bits (even positions)
    }
    
    // Calculate offsets
    signal latOffset <== (isDir[0].out + isDir[1].out + isDir[7].out) * 100000 -
                        (isDir[3].out + isDir[4].out + isDir[5].out) * 100000;
    
    signal lngOffset <== (isDir[1].out + isDir[2].out + isDir[3].out) * 100000 -
                        (isDir[5].out + isDir[6].out + isDir[7].out) * 100000;
    
    // Calculate potential new coordinates
    signal rawNewLat <== latNum.out + latOffset;
    signal rawNewLng <== lngNum.out + lngOffset;
    
    // Properly handle latitude bounds (0 to 180000000)
    component latUnderflow = LessThan(32);  // Check if < 0
    latUnderflow.in[0] <== rawNewLat;
    latUnderflow.in[1] <== 0;
    
    component latOverflow = LessThan(32);   // Check if > 180000000
    latOverflow.in[0] <== 180000000;
    latOverflow.in[1] <== rawNewLat;
    
    // Adjust latitude based on underflow/overflow
    signal newLat <== 
        latUnderflow.out * 0 + 
        latOverflow.out * 180000000 +
        (1 - latUnderflow.out - latOverflow.out) * rawNewLat;
    
    // Properly handle longitude wrapping (0 to 360000000)
    component lngUnderflow = LessThan(32);  // Check if < 0
    lngUnderflow.in[0] <== rawNewLng;
    lngUnderflow.in[1] <== 0;
    
    component lngOverflow = LessThan(32);   // Check if > 360000000
    lngOverflow.in[0] <== 360000000;
    lngOverflow.in[1] <== rawNewLng;
    
    // Calculate wrapped longitude
    signal lngUnderflowAdjust <== lngUnderflow.out * 360000000;
    signal lngOverflowAdjust <== lngOverflow.out * 360000000;
    
    signal newLng <== rawNewLng + lngUnderflowAdjust - lngOverflowAdjust;
    
    // Encode new coordinates
    component encoder = Geohash(32);
    encoder.lat <== newLat;
    encoder.lng <== newLng;
    
    // Copy outputs
    neighbor <== encoder.bits;
    chars <== encoder.chars;
}
