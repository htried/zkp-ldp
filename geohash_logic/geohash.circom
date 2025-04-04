pragma circom 2.2.0;

include "circuits/bitify.circom";
include "circuits/comparators.circom";
include "circuits/gates.circom";

// ---- Basic Bit Operations ----

// Interleave bits from two arrays into one array
template Interleave() {
    signal input even[32];
    signal input odd[32];
    signal output out[64];

    // Simple interleaving: even bits from first array, odd bits from second array
    for (var i = 0; i < 32; i++) {
        out[2*i] <== even[i];
        out[2*i + 1] <== odd[i];
    }
}

// Squash even bitlevels of X into a 32-bit word
template Squash() {
    signal input X[64]; // 64-bit input
    signal output out[32]; // 32-bit output with even bits from input
    
    // Extract even bits
    for (var i = 0; i < 32; i++) {
        out[i] <== X[i*2];
    }
}

// Deinterleave 64 bits into two 32-bit words with even and odd bits
template Deinterleave() {
    signal input X[64]; // 64-bit input
    signal output even[32]; // 32-bit output with even bits
    signal output odd[32]; // 32-bit output with odd bits
    
    // Extract even bits
    component squashEven = Squash();
    squashEven.X <== X;
    even <== squashEven.out;
    
    // Extract odd bits
    signal oddBits[64];
    for (var i = 0; i < 63; i++) {
        oddBits[i] <== X[i+1];
    }
    oddBits[63] <== 0;
    
    component squashOdd = Squash();
    squashOdd.X <== oddBits;
    odd <== squashOdd.out;
}

// ---- Main Templates ----

template Geohash(precision) {
    signal input lat;    // (Latitude + 90) * 1e6  (0 to 180000000)
    signal input lng;    // (Longitude + 180) * 1e6 (0 to 360000000)
    signal output bits[64];    // Binary geohash
    signal output chars[12];   // Base32 character indices
    
    // Convert inputs to bits
    component latBits = Num2Bits(28); // 2^28 > 180000000
    component lngBits = Num2Bits(29); // 2^29 > 360000000
    
    latBits.in <== lat;
    lngBits.in <== lng;
    
    // Prepare arrays for interleaving - we'll reverse the bits here to MSB order
    signal latArray[32];
    signal lngArray[32];
    
    // Fill arrays with bits in MSB order
    for (var i = 0; i < 32; i++) {
        if (i < 28) {
            latArray[i] <== latBits.out[27-i];  // Reverse to MSB order
        } else {
            latArray[i] <== 0;
        }
        if (i < 29) {
            lngArray[i] <== lngBits.out[28-i];  // Reverse to MSB order
        } else {
            lngArray[i] <== 0;
        }
    }
    
    // Interleave the bits
    component interleaver = Interleave();
    interleaver.even <== latArray;
    interleaver.odd <== lngArray;
    bits <== interleaver.out;
    
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
    component latNum = Bits2Num(28);
    component lngNum = Bits2Num(29);
    
    // Connect bits in MSB order
    for (var i = 0; i < 28; i++) {
        latNum.in[i] <== deinterleaver.even[27-i];  // Reverse to get MSB first
    }
    for (var i = 0; i < 29; i++) {
        lngNum.in[i] <== deinterleaver.odd[28-i];   // Reverse to get MSB first
    }
    
    // Calculate offsets (using smaller offset value)
    signal latOffset <== (isDir[0].out + isDir[1].out + isDir[7].out) * 100000 -
                        (isDir[3].out + isDir[4].out + isDir[5].out) * 100000;
    
    signal lngOffset <== (isDir[1].out + isDir[2].out + isDir[3].out) * 100000 -
                        (isDir[5].out + isDir[6].out + isDir[7].out) * 100000;
    
    // Calculate new coordinates (fix normalization)
    signal newLat <== latNum.out + latOffset;  // Already normalized
    signal newLng <== lngNum.out + lngOffset;  // Already normalized
    
    // Encode new coordinates
    component encoder = Geohash(32);
    encoder.lat <== newLat;
    encoder.lng <== newLng;
    
    // Copy outputs
    neighbor <== encoder.bits;
    chars <== encoder.chars;
}
