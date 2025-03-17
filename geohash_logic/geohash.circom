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

// ---- Integer Coordinates Encoding (Simple Version) ----

// Encode integer coordinates to a geohash
template EncodeIntWithPrecisionSimple(MAX_BITS) {
    signal input lat; // Latitude * 1000 (range: 0 to 90000)
    signal input lng; // Longitude * 1000 (range: 0 to 360000)
    signal input bits; // Number of bits of precision
    signal output hash[MAX_BITS]; // Geohash with specified precision
    
    // Check input ranges
    component latInRange = LessThan(20);
    latInRange.in[0] <== lat;
    latInRange.in[1] <== 90001; // Max 90.000
    latInRange.out === 1;
    
    component lngInRange = LessThan(20);
    lngInRange.in[0] <== lng;
    lngInRange.in[1] <== 360001; // Max 360.000
    lngInRange.out === 1;
    
    // Convert lat/lng to bit arrays (using smaller bit widths to avoid overflow)
    component latBits = Num2Bits(18);  // 2^18 = 262,144 > 90,000
    latBits.in <== lat;
    
    component lngBits = Num2Bits(19);  // 2^19 = 524,288 > 360,000
    lngBits.in <== lng;
    
    // Create arrays to hold all 32 bits
    signal latFullBits[32];
    signal lngFullBits[32];
    
    // Copy the bits we have, pad with zeros
    for (var i = 0; i < 32; i++) {
        if (i < 18) {
            latFullBits[i] <== latBits.out[i];
        } else {
            latFullBits[i] <== 0;
        }
        
        if (i < 19) {
            lngFullBits[i] <== lngBits.out[i];
        } else {
            lngFullBits[i] <== 0;
        }
    }
    
    // Interleave the bits
    component interleaver = Interleave();
    interleaver.even <== latFullBits;
    interleaver.odd <== lngFullBits;
    
    // Truncate to the specified precision
    component lessThan[MAX_BITS];
    for (var i = 0; i < MAX_BITS; i++) {
        lessThan[i] = LessThan(8);
        lessThan[i].in[0] <== i;
        lessThan[i].in[1] <== bits;
        
        hash[i] <== lessThan[i].out * interleaver.out[i];
    }
}

// ---- Float Coordinates Encoding (Traditional Version) ----

// Specialized template for latitude encoding
template EncodeLatitude() {
    signal input lat;  // Latitude (-90 to 90)
    signal output out; // 32-bit encoded value
    
    signal normalized <== (lat + 90) * 23860929;
    out <== normalized;
}

// Specialized template for longitude encoding
template EncodeLongitude() {
    signal input lng;  // Longitude (-180 to 180)
    signal output out; // 32-bit encoded value
    
    signal normalized <== (lng + 180) * 11930465;
    out <== normalized;
}

// Encode float latitude and longitude to a geohash integer
template EncodeInt() {
    signal input lat; // Latitude
    signal input lng; // Longitude
    signal output hash[64]; // 64-bit geohash
    
    // Encode lat and lng to 32-bit integers
    component encLat = EncodeLatitude();
    encLat.lat <== lat;
    
    component encLng = EncodeLongitude();
    encLng.lng <== lng;
    
    // Convert to bit arrays
    component latBits = Num2Bits(32);
    latBits.in <== encLat.out;
    
    component lngBits = Num2Bits(32);
    lngBits.in <== encLng.out;
    
    // Interleave the bits
    component interleaver = Interleave();
    interleaver.even <== latBits.out;
    interleaver.odd <== lngBits.out;
    
    hash <== interleaver.out;
}

// Encode with precision - takes only the most significant bits
template EncodeIntWithPrecision(MAX_BITS) {
    signal input lat; // Latitude
    signal input lng; // Longitude
    signal input bits; // Number of bits of precision
    signal output hash[MAX_BITS]; // Geohash with specified precision
    
    // First encode to full 64-bit hash
    component encoder = EncodeInt();
    encoder.lat <== lat;
    encoder.lng <== lng;
    
    component lessThan[MAX_BITS];
    // Use a fixed loop based on the template parameter
    for (var i = 0; i < MAX_BITS; i++) {
        // Create a component to check if i < bits
        lessThan[i] = LessThan(8);
        lessThan[i].in[0] <== i;
        lessThan[i].in[1] <== bits;
        
        // Use the result to conditionally assign values
        hash[i] <== lessThan[i].out * encoder.hash[i];
    }
}

// ---- Decoding Functions ----

// Decode a 32-bit value to latitude
template DecodeLatitude() {
    signal input encoded;  // 32-bit encoded value
    signal output lat;     // Latitude (-90 to 90)
    
    // Use witness computation for division
    signal normalized <-- encoded / 4294967296;
    
    // Add constraint to ensure normalized is correct
    encoded === normalized * 4294967296;
    
    // Convert to latitude range
    lat <== normalized * 180 - 90;
}

// Decode a 32-bit value to longitude
template DecodeLongitude() {
    signal input encoded;  // 32-bit encoded value
    signal output lng;     // Longitude (-180 to 180)
    
    // Use witness computation for division
    signal normalized <-- encoded / 4294967296;
    
    // Add constraint to ensure normalized is correct
    encoded === normalized * 4294967296;
    
    // Convert to longitude range
    lng <== normalized * 360 - 180;
}

// Decode a geohash to latitude and longitude
template DecodeInt() {
    signal input hash[64]; // 64-bit geohash
    signal output lat; // Latitude
    signal output lng; // Longitude
    
    // Deinterleave the bits
    component deinterleaver = Deinterleave();
    deinterleaver.X <== hash;
    
    // Convert bit arrays back to numbers
    component latBits = Bits2Num(32);
    latBits.in <== deinterleaver.even;
    
    component lngBits = Bits2Num(32);
    lngBits.in <== deinterleaver.odd;
    
    // Decode the values
    component decLat = DecodeLatitude();
    decLat.encoded <== latBits.out;
    
    component decLng = DecodeLongitude();
    decLng.encoded <== lngBits.out;
    
    // Set outputs
    lat <== decLat.lat;
    lng <== decLng.lng;
}

// ---- Scaled Input Handling ----

// Handle scaled inputs for floating-point values
template EncodeIntWithPrecisionScaled(MAX_BITS) {
    signal input lat;        // Scaled latitude (integer)
    signal input lng;        // Scaled longitude (integer)
    signal input bits;       // Number of bits of precision
    signal input scale_factor; // Scaling factor used
    signal output hash[MAX_BITS]; // Geohash with specified precision
    
    // Descale the inputs
    signal lat_descaled <-- lat / scale_factor;
    signal lng_descaled <-- lng / scale_factor;
    
    // Ensure the descaling is correct
    lat === lat_descaled * scale_factor;
    lng === lng_descaled * scale_factor;
    
    // Use the original template with descaled values
    component encoder = EncodeIntWithPrecision(MAX_BITS);
    encoder.lat <== lat_descaled;
    encoder.lng <== lng_descaled;
    encoder.bits <== bits;
    
    // Connect the output
    hash <== encoder.hash;
}

// ---- Simple Neighbor Function ----

// Corrected SimpleNeighbor template with declarations outside loops
template SimpleNeighbor() {
    signal input hash[64];  // Input geohash bits
    signal input direction; // Direction (0-7): N, NE, E, SE, S, SW, W, NW
    signal output neighbor[64]; // Output neighbor geohash bits
    
    // Direction components - defined outside any loops
    component isDir[8];
    for (var d = 0; d < 8; d++) {
        isDir[d] = IsEqual();
        isDir[d].in[0] <== direction;
        isDir[d].in[1] <== d;
    }
    
    // XOR components for each bit - defined outside loops
    component xors[64];
    for (var i = 0; i < 64; i++) {
        xors[i] = XOR();
    }
    
    // Signal arrays for direction components - defined outside loops
    signal northComponent[64];
    signal eastComponent[64];
    signal southComponent[64];
    signal westComponent[64];
    signal flipBit[64];
    
    // Now process each bit
    for (var i = 0; i < 64; i++) {
        // North (0): Flip even bits (latitude) in range 44-50
        var northMask = 0;
        if (i % 2 == 0 && i >= 44 && i < 52) northMask = 1;
        
        // East (2): Flip odd bits (longitude) in range 45-51
        var eastMask = 0;
        if (i % 2 == 1 && i >= 45 && i < 53) eastMask = 1;
        
        // South (4): Flip even bits (latitude) in range 44-50
        var southMask = 0;
        if (i % 2 == 0 && i >= 44 && i < 52) southMask = 1;
        
        // West (6): Flip odd bits (longitude) in range 45-51
        var westMask = 0;
        if (i % 2 == 1 && i >= 45 && i < 53) westMask = 1;
        
        // Calculate the combined mask based on direction
        northComponent[i] <== northMask * (isDir[0].out + isDir[1].out + isDir[7].out);
        eastComponent[i] <== eastMask * (isDir[1].out + isDir[2].out + isDir[3].out);
        southComponent[i] <== southMask * (isDir[3].out + isDir[4].out + isDir[5].out);
        westComponent[i] <== westMask * (isDir[5].out + isDir[6].out + isDir[7].out);
        
        // Combine all components
        flipBit[i] <== northComponent[i] + eastComponent[i] + southComponent[i] + westComponent[i];
        
        // Apply the XOR operation
        xors[i].a <== hash[i];
        xors[i].b <== flipBit[i];
        neighbor[i] <== xors[i].out;
    }
}