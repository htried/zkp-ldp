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
    signal input lat;    // (Latitude + 180) * 1e6
    signal input lng;    // (Longitude + 360) * 1e6
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
    signal input hash[64];      // Input geohash bits
    signal input direction;     // Direction (0-7): N, NE, E, SE, S, SW, W, NW
    signal input offset;        // Offset in degrees * 1e6
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
    
    // Calculate offsets using the input offset parameter
    // Break down into quadratic constraints

    // First calculate the positive and negative components separately
    signal latOffsetPositive <== (isDir[0].out + isDir[1].out + isDir[7].out) * offset;
    signal latOffsetNegative <== (isDir[3].out + isDir[4].out + isDir[5].out) * offset;

    // Then combine them
    signal latOffset <== latOffsetPositive - latOffsetNegative;

    // Similarly for longitude
    signal lngOffsetPositive <== (isDir[1].out + isDir[2].out + isDir[3].out) * offset;
    signal lngOffsetNegative <== (isDir[5].out + isDir[6].out + isDir[7].out) * offset;

    // Then combine them
    signal lngOffset <== lngOffsetPositive - lngOffsetNegative;
    
    // Calculate potential new coordinates
    signal rawNewLat <== latNum.out + latOffset;

    // Check if we're crossing the North Pole (exceeding 90°)
    component crossingNorthPole = GreaterEqThan(32);
    crossingNorthPole.in[0] <== rawNewLat;
    crossingNorthPole.in[1] <== 270000000;  // 90° + 180° shift

    // Check if we're crossing the South Pole (going below -90°)
    component crossingSouthPole = LessThan(32);
    crossingSouthPole.in[0] <== rawNewLat;
    crossingSouthPole.in[1] <== 90000000;   // -90° + 180° shift

    // Break down the selection into quadratic constraints
    signal isNormalCase <== 1 - crossingNorthPole.out - crossingSouthPole.out;

    // Calculate how far we went over/under the limits
    signal northOverflow <== rawNewLat - 270000000;  // How far over North Pole
    signal southUnderflow <== 90000000 - rawNewLat;  // How far under South Pole

    // Calculate each case separately
    signal tempLat1 <== crossingNorthPole.out * (270000000 - northOverflow);  // North Pole case: reflect back from max
    signal tempLat2 <== crossingSouthPole.out * (90000000 + southUnderflow);  // South Pole case: reflect back from min
    signal tempLat3 <== isNormalCase * rawNewLat;           // Normal case

    // Combine the results
    signal newLat <== tempLat1 + tempLat2 + tempLat3;

    // For longitude, we need to flip it by 180° when crossing either pole
    signal isLngFlip <== crossingNorthPole.out + crossingSouthPole.out;
    signal isNotLngFlip <== 1 - isLngFlip;

    signal rawNewLng <== lngNum.out + lngOffset;

    // Check if we need to wrap around the 180° boundary
    component lngOverflow = GreaterEqThan(32);
    lngOverflow.in[0] <== rawNewLng;
    lngOverflow.in[1] <== 540000000;  // 180° + 360° shift

    component lngUnderflow = LessThan(32);
    lngUnderflow.in[0] <== rawNewLng;
    lngUnderflow.in[1] <== 180000000;  // -180° + 360° shift

    // First handle potential underflow/overflow
    signal tempLng1 <== rawNewLng;
    signal tempLng2 <== tempLng1 + (lngUnderflow.out * 360000000);
    signal tempLng3 <== tempLng2 - (lngOverflow.out * 360000000);

    // Then handle potential pole-crossing flip
    signal tempLng4 <== tempLng3 + 180000000;  // Flip by 180°

    // Check if the flipped longitude needs wrapping
    component flippedLngOverflow = GreaterEqThan(32);
    flippedLngOverflow.in[0] <== tempLng4;
    flippedLngOverflow.in[1] <== 540000000;  // 180° + 360° shift

    component flippedLngUnderflow = LessThan(32);
    flippedLngUnderflow.in[0] <== tempLng4;
    flippedLngUnderflow.in[1] <== 180000000;  // -180° + 360° shift

    // Wrap the flipped longitude if needed
    signal tempLng5 <== tempLng4 + (flippedLngUnderflow.out * 360000000);
    signal tempLng6 <== tempLng5 - (flippedLngOverflow.out * 360000000);

    // Finally select between flipped and unflipped versions of the longitude
    signal tempLng7 <== isLngFlip * tempLng6;
    signal tempLng8 <== isNotLngFlip * tempLng3;

    signal newLng <== tempLng7 + tempLng8;

    // Encode new coordinates
    component encoder = Geohash(32);
    encoder.lat <== newLat;
    encoder.lng <== newLng;
    
    // Copy outputs
    neighbor <== encoder.bits;
    chars <== encoder.chars;
}
