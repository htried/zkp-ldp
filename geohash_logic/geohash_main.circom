pragma circom 2.2.0;

include "./geohash.circom";

// Main component for encoding geohash with integer coordinates
component main {public [lat, lng, bits]} = EncodeIntWithPrecisionSimple(64);
