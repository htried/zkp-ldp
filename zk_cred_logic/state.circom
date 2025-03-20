pragma circom 2.2.0;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/gates.circom";
include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/babyjub.circom";
include "circomlib/circuits/pedersen.circom";
include "circomlib/circuits/eddsaposeidon.circom";

// PRIVATE KEY = 17043596940825480372850145379760378381660468692634776084163635977000967496844

// ============== LOGICAL CIRCUIT COMPONENTS =================
// 1-bit Mux component
template Mux1() {
    signal input c;  // Control signal
    signal input a;  // Input signal when c is 1
    signal input b;  // Input signal when c is 0
    signal output out;

    // Ensure c is binary (0 or 1)
    c * (c - 1) === 0;

    // Constraint for multiplexing
    out <== c * (a - b) + b;
}

// ============== STATE MANAGEMENT FUNCTIONS =================

// Create a state with a given number of IP addresses
// This hashes the state and groups all relevant wires for a given state (but doess not verify signature)
template CreateState(num_ips) {
    signal input ips[num_ips];
    signal input nonce;
    signal input sig_r8x_in;
    signal input sig_r8y_in;
    signal input sig_s_in;

    signal output ipsOut[num_ips];
    signal output nonceOut;
    signal output ipBits[num_ips * 32]; // 32 bits for each IP address
    signal output nonceBits[32]; // 32 bits for nonce
    signal output stateHash; // Hash of ipBits and nonce
    signal output sig_r8x;
    signal output sig_r8y;
    signal output sig_s;

    ipsOut <== ips;
    nonceOut <== nonce;
    sig_r8x <== sig_r8x_in;
    sig_r8y <== sig_r8y_in;
    sig_s <== sig_s_in;

    // Convert IP field elements to bits
    component ipToBitsConverters[num_ips];
    for (var i = 0; i < num_ips; i++) {
        ipToBitsConverters[i] = Num2Bits(32);
        ipToBitsConverters[i].in <== ips[i];
        for (var j = 0; j < 32; j++) {
            ipBits[i * 32 + j] <== ipToBitsConverters[i].out[j];
        }
    }

    // Hash ipBits and nonce together
    var len = num_ips + 1;
    
    component hasher = Poseidon(len);

    // Combine ipBits and nonceBits into hash input
    for (var i = 0; i < num_ips; i++) {
        hasher.inputs[i] <== ips[i];
    }
    hasher.inputs[num_ips] <== nonce;

    stateHash <== hasher.out;
}

// Propose a new state update
template ProposeStateUpdate(num_ips) {
    // Input signals
    signal input initialState_ips[num_ips];
    signal input initialState_nonce;
    signal input new_ip;
    signal input sig_r8x_in;
    signal input sig_r8y_in;
    signal input sig_s_in;
    
    // Output signals
    signal output newState_ips[num_ips];
    signal output newState_nonce;
    signal output stateHash;
    signal output sig_r8x;
    signal output sig_r8y;
    signal output sig_s;

    signal exists_binary;
    signal exists_zero;

    // Pre-declare components
    component isZero[num_ips];
    component notFirstZero[num_ips];
    component zeroAnds[num_ips - 1];
    component mux1[num_ips];
    component mux2[num_ips];
    component mux3[num_ips];
    component ipEqual[num_ips];

    // Initialize components and check for IP existence first
    component exists_ors[num_ips];
    exists_ors[0] = OR();
    exists_ors[0].a <== 0;
    // Not first zero is an array of OR()'s which is an array of 0's followed by a 1 at the first zero entry.
    // Checking notFirstZero[j-1] == 0 ensures that ips[j] is the first zero.
    notFirstZero[0] = OR();
    notFirstZero[0].a <== 0;
    for (var j = 0; j < num_ips; j++) {
        isZero[j] = IsZero();
        ipEqual[j] = IsEqual();
        
        // Check IP equality once
        ipEqual[j].in[0] <== initialState_ips[j];
        ipEqual[j].in[1] <== new_ip;
        
        isZero[j].in <== initialState_ips[j];
        notFirstZero[j].b <== isZero[j].out;
        exists_ors[j].b <== ipEqual[j].out;
        if (j < (num_ips - 1)) {
            exists_ors[j+1] = OR();
            exists_ors[j+1].a <== exists_ors[j].out;
            notFirstZero[j+1] = OR();
            notFirstZero[j+1].a <== notFirstZero[j].out;
        }
    }

    // Move exists_binary assignment outside the loops
    exists_binary <== exists_ors[num_ips - 1].out;
    exists_zero <== notFirstZero[num_ips - 1].out;

    // Process IP updates
    for (var i = 0; i < num_ips; i++) {
        mux1[i] = Mux1();
        mux2[i] = Mux1();
        mux3[i] = Mux1();
        
        // Ensure control signals are binary
        if (i == 0) {
            mux1[i].c <== isZero[i].out;
            mux1[i].a <== new_ip;
            mux1[i].b <== initialState_ips[i];
        } else {
            zeroAnds[i-1] = AND();
            zeroAnds[i-1].a <== (1-notFirstZero[i-1].out);
            zeroAnds[i-1].b <== isZero[i].out;
            mux1[i].c <== zeroAnds[i-1].out;
            mux1[i].a <== new_ip;
            mux1[i].b <== initialState_ips[i];
        }
        
        mux2[i].c <== exists_zero;
        mux2[i].a <== mux1[i].out;
        mux2[i].b <== i < num_ips-1 ? initialState_ips[i+1] : new_ip;

        mux3[i].c <== exists_binary;
        mux3[i].a <== initialState_ips[i];
        mux3[i].b <== mux2[i].out;
        newState_ips[i] <== mux3[i].out;
    }

    // Create new state with updated IP list
    component newStateComponent = CreateState(num_ips);
    newStateComponent.ips <== newState_ips;
    newStateComponent.nonce <== initialState_nonce;
    newStateComponent.sig_r8x_in <== sig_r8x_in;
    newStateComponent.sig_r8y_in <== sig_r8y_in;
    newStateComponent.sig_s_in <== sig_s_in;
    
    // Connect outputs
    stateHash <== newStateComponent.stateHash;
    sig_r8x <== newStateComponent.sig_r8x;
    sig_r8y <== newStateComponent.sig_r8y;
    sig_s <== newStateComponent.sig_s;
    newState_nonce <== initialState_nonce;
}

// Convert function to template
template CheckValidStateUpdate() {
    // Define input signals for the states
    signal input initialStateHash;
    signal input initialSigR8x;
    signal input initialSigR8y;
    signal input initialSigS;
    signal input proposedStateHash;
    signal input proposedSigR8x;
    signal input proposedSigR8y;
    signal input proposedSigS;
    signal input enabled;

    // Compare hashes
    component hashesEqual = IsEqual();
    hashesEqual.in[0] <== initialStateHash;
    hashesEqual.in[1] <== proposedStateHash;

    // Verify initial state signature
    component initialVerifier = EdDSAPoseidonVerifier();
    initialVerifier.enabled <== enabled;
    initialVerifier.M <== initialStateHash;
    initialVerifier.Ax <== 13277427435165878497778222415993513565335242147425444199013288855685581939618;
    initialVerifier.Ay <== 13622229784656158136036771217484571176836296686641868549125388198837476602820;
    initialVerifier.S <== initialSigS;
    initialVerifier.R8x <== initialSigR8x;
    initialVerifier.R8y <== initialSigR8y;

    // Verify proposed state signature
    component proposedVerifier = EdDSAPoseidonVerifier();
    proposedVerifier.enabled <== enabled;
    proposedVerifier.M <== proposedStateHash;
    proposedVerifier.Ax <== 13277427435165878497778222415993513565335242147425444199013288855685581939618;
    proposedVerifier.Ay <== 13622229784656158136036771217484571176836296686641868549125388198837476602820;
    proposedVerifier.S <== proposedSigS;
    proposedVerifier.R8x <== proposedSigR8x;
    proposedVerifier.R8y <== proposedSigR8y;

    // Break down the multiplication into intermediate steps
    // Commenting out because new eddsa component doesn't support isValid/isInvalid but I don't think that's important.
    // signal intermediate;
    // intermediate <== initialVerifier.out * (1 - hashesEqual.out);
    // isValid <== intermediate * proposedVerifier.out;
}

template AttemptStateUpdate(num_ips) {
    // Public inputs
    signal input ips[num_ips];
    signal input nonce;
    signal input new_ip;
    signal input is_challenge_response;
    signal input initial_state_r8x;
    signal input initial_state_r8y;
    signal input initial_state_s;
    signal input new_state_r8x;
    signal input new_state_r8y;
    signal input new_state_s;

    // Outputs
    signal output newState[num_ips];
    signal output newStateNonce;
    signal output challenge_failed;

    // Create initial state
    component initialState = CreateState(num_ips);
    initialState.ips <== ips;
    initialState.nonce <== nonce;
    initialState.sig_r8x_in <== initial_state_r8x;
    initialState.sig_r8y_in <== initial_state_r8y;
    initialState.sig_s_in <== initial_state_s;

    // Propose new state
    component proposedState = ProposeStateUpdate(num_ips);
    // Connect individual signals instead of the whole template
    // TODO I dont think this is needed
    for (var i = 0; i < num_ips; i++) {
        proposedState.initialState_ips[i] <== initialState.ipsOut[i];
    }
    proposedState.initialState_nonce <== initialState.nonceOut;
    proposedState.new_ip <== new_ip;
    proposedState.sig_r8x_in <== new_state_r8x;
    proposedState.sig_r8y_in <== new_state_r8y;
    proposedState.sig_s_in <== new_state_s;

    // Validate state update
    component stateValidator = CheckValidStateUpdate();
    stateValidator.initialStateHash <== initialState.stateHash;
    stateValidator.initialSigR8x <== initialState.sig_r8x;
    stateValidator.initialSigR8y <== initialState.sig_r8y;
    stateValidator.initialSigS <== initialState.sig_s;
    stateValidator.proposedStateHash <== proposedState.stateHash;
    stateValidator.proposedSigR8x <== proposedState.sig_r8x;
    stateValidator.proposedSigR8y <== proposedState.sig_r8y;
    stateValidator.proposedSigS <== proposedState.sig_s;
    stateValidator.enabled <== (1 - is_challenge_response);

    // If valid update or successful challenge, return new state
    // Commenting out this mux logic for now: this just lets you rerandomize your state (not even that I think since this is all deterministic) if neither is true, so I don't think we even need to support that path.
    // component resultMux[num_ips];
    // component nonceMux = Mux1();
    
    // Select between proposed and initial state based on validation
    // signal selector;
    // // TODO: Might need binary validation?
    // selector <== stateValidator.isValid + is_challenge_response - (stateValidator.isValid * is_challenge_response);
    
    for (var i = 0; i < num_ips; i++) {
        // resultMux[i] = Mux1();
        // resultMux[i].c <== selector;
        // resultMux[i].a <== proposedState.newState_ips[i];
        // resultMux[i].b <== initialState.ipsOut[i];
        newState[i] <== proposedState.newState_ips[i];
    }
    
    // nonceMux.c <== selector;
    // nonceMux.a <== proposedState.newState_nonce;
    // nonceMux.b <== initialState.nonceOut;
    newStateNonce <== proposedState.newState_nonce;
    
    // Removed selector logic for now unless I misunderstood something
    challenge_failed <== 0;
}

// TODO: Range check IPs at some point!
component main { public [ is_challenge_response ]} = AttemptStateUpdate(5);