pragma circom 2.2.0;

include "circuits/bitify.circom";
include "circuits/comparators.circom";

template DebugCircuit() {
    signal input value;
    signal output bits[32];
    signal output is_in_range;
    
    // Check if the value is in range
    component range_check = LessThan(32);
    range_check.in[0] <== value;
    range_check.in[1] <== 360001;
    is_in_range <== range_check.out;
    
    // Convert to bits
    component num2bits = Num2Bits(32);
    num2bits.in <== value;
    bits <== num2bits.out;
}

// A minimal circuit to test Num2Bits with our inputs
component main {public [value]} = DebugCircuit();
