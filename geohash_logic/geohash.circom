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
    
    // For longitude wrapping, handle each case separately
    signal rawNewLng <== lngNum.out + lngOffset;

    // Check for underflow (result < 0)
    component isUnderflow = LessThan(32);
    isUnderflow.in[0] <== rawNewLng;
    isUnderflow.in[1] <== 0;

    // Check for overflow (result >= 360000000)
    component isOverflow = GreaterEqThan(32);
    isOverflow.in[0] <== rawNewLng;
    isOverflow.in[1] <== 360000000;

    // Calculate each potential outcome separately
    signal wrapPositive <== rawNewLng + 360000000;
    signal wrapNegative <== rawNewLng - 360000000;

    // Apply wrapping only when needed
    signal tempLng <== rawNewLng + (isUnderflow.out * 360000000);
    signal newLng <== tempLng - (isOverflow.out * 360000000);
    
    // Encode new coordinates
    component encoder = Geohash(32);
    encoder.lat <== rawNewLat;
    encoder.lng <== newLng;
    
    // Copy outputs
    neighbor <== encoder.bits;
    chars <== encoder.chars;
}
