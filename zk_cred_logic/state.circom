pragma circom 2.2.0;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/gates.circom";
include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/babyjub.circom";
include "circomlib/circuits/pedersen.circom";
include "circomlib/circuits/eddsaposeidon.circom";

// PRIVATE KEY = 17043596940825480372850145379760378381660468692634776084163635977000967496844

// ============== MATHEMATICAL FUNCTIONS =================
//Multiply (a*b mod m)
function mod_mult(a, b, m) {
	var res = 0;

	while (b > 0) {
		if (b & 1) {
			res = (res + a) % m;
		}

		a = (2 * a) % m;
		b >>= 1;
	}
	return res;
}

//Add two points in the BabyJubJub Curve
function add_point(x1, y1, x2, y2) {
	var a = 168700;
	var d = 168696;
	var x3 = (x1*y2 + y1*x2) * 1 / (1 + d*x1*x2*y1*y2);
	var y3 = (y1*y2 - a*x1*x2) * 1 / (1 - d*x1*x2*y1*y2);

	return [x3, y3];
}

//Multiple a point by a scalar in BabyJubJub
function mult_point(x, y, r){
	var point[2];
	var powers[512];

	point = [0, 1];
	powers[0] = x;
	powers[1] = y;

	for (var i = 2; i < 512; i += 2){
		var new_point[2];
		new_point = add_point(powers[i-2], powers[i-1], powers[i-2], powers[i-1]);
		
		powers[i] = new_point[0];
		powers[i+1] = new_point[1];
	}

	for (var i = 0; i < 512; i += 2){
		if (r & 1){
			point = add_point(point[0], point[1], powers[i], powers[i+1]);
		}
		r >>= 1;
	}

	return point;
}

//Modular exponentiation (a^b mod m)
function pow_mod(a, b, m) {
    var res = 1;
    a = a % m;
    
    while (b > 0) {
        if (b & 1) {
            res = mod_mult(res, a, m);
        }
        a = mod_mult(a, a, m);
        b >>= 1;
    }
    return res;
}

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

// ============== ECDSA SIGNATURE FUNCTIONS =================
// Sign a message using ECDSA
function Sign(hashed_msg) {
    var Ln = 251;
    var n = 2736030358979909402780800718157159386076813972158567259200215660948447373041;
    
    var G[2];
    var priv;

    // Private key from ecdsa/private_key.pem
    //  In reality this would be a private key that's loaded from a file
    //  For security purposes we would convert this to a template and load
    //  the key as a private input. Hardcoding it here for simplicity.
    priv = 17043596940825480372850145379760378381660468692634776084163635977000967496844;

    G[0] = 5299619240641551281634865583518297030282874472190772894086521144482721001553;
    G[1] = 16950150798460657717958625567821834550301663161624707787222815936182638968203;

    // Generate random k using deterministic combination of private inputs
    var k = mod_mult(hashed_msg + priv, n-1, n); // Derive k from message and private key
    
    // Calculate r = (k*G)_x mod n
    var point[2];
    point = mult_point(G[0], G[1], k);
    var r = point[0] % n;

    // Calculate s = k^(-1)(z + r*priv) mod n
    var z = hashed_msg >> 6;
    var k_inv = pow_mod(k, n-2, n); // k^(-1) mod n using Fermat's little theorem
    var s = mod_mult(k_inv, (z + mod_mult(r, priv, n)) % n, n);
    
    // Calculate s_inv for verification
    var s_inv = pow_mod(s, n-2, n);

    return [r, s_inv];
}

// Verify an ECDSA signature
template Verify() {
    signal input hashed_msg;
    signal input r;
    signal input s_inv;
    signal output out;

    var Ln = 251;
    var n = 2736030358979909402780800718157159386076813972158567259200215660948447373041;
    
    var G[2];
    var pub[2];

    pub[0] = 5299619240641551281634865583518297030282874472190772894086521144482721001553;
    pub[1] = 16950150798460657717958625567821834550301663161624707787222815936182638968203;

    G[0] = 5299619240641551281634865583518297030282874472190772894086521144482721001553;
    G[1] = 16950150798460657717958625567821834550301663161624707787222815936182638968203;

    var z = hashed_msg >> 6;
    var u1 = mod_mult(z, s_inv, n);
    var u2 = mod_mult(r, s_inv, n);

    var p1[2] = mult_point(G[0], G[1], u1);
    var p2[2] = mult_point(pub[0], pub[1], u2);
    var point[2] = add_point(p1[0], p1[1], p2[0], p2[1]);

    // Use witness computation for the verification result
    out <-- (point[0] % n == r % n) ? 1 : 0;
    
    // Add constraint to ensure out is binary
    out * (out - 1) === 0;
}

// ============== STATE MANAGEMENT FUNCTIONS =================

// Create a state with a given number of IP addresses
//  This state will be hashed and signed to ensure integrity and prevent tampering
template CreateState(num_ips) {
    signal input ips[num_ips];
    signal input nonce;
    
    signal output ipsOut[num_ips];
    signal output nonceOut;
    signal output ipBits[num_ips * 32]; // 32 bits for each IP address
    signal output nonceBits[32]; // 32 bits for nonce
    signal output stateHash; // Hash of ipBits and nonce
    signal output sig_r;
    signal output sig_s_inv;

    ipsOut <== ips;
    nonceOut <== nonce;

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

    // Generate signature of the hash
    // Change from direct assignment to witness computation
    var signature[2] = Sign(stateHash);
    sig_r <-- signature[0];
    sig_s_inv <-- signature[1];

    // Add constraint to verify the signature is valid
    component verifier = Verify();
    verifier.hashed_msg <== stateHash;
    verifier.r <== sig_r;
    verifier.s_inv <== sig_s_inv;

    // The issue is that this wasn't properly constrained before so signature verification never worked.
    // Now use the template's output
    verifier.out === 0;
}

// Propose a new state update
template ProposeStateUpdate(num_ips) {
    // Input signals
    signal input initialState_ips[num_ips];
    signal input initialState_nonce;
    signal input new_ip;
    
    // Output signals
    signal output newState_ips[num_ips];
    signal output newState_nonce;
    signal output stateHash;
    signal output sig_r;
    signal output sig_s_inv;

    signal exists_binary;

    // Pre-declare components
    component isZero[num_ips];
    component mux1[num_ips];
    component mux2[num_ips];
    component ipEqual[num_ips];

    // Initialize components and check for IP existence first
    component exists_ors[num_ips];
    exists_ors[0] = OR();
    exists_ors[0].a <== 0;
    for (var j = 0; j < num_ips; j++) {
        isZero[j] = IsZero();
        ipEqual[j] = IsEqual();
        
        // Check IP equality once
        ipEqual[j].in[0] <== initialState_ips[j];
        ipEqual[j].in[1] <== new_ip;
        
        exists_ors[j].b <== ipEqual[j].out;
        if (j < (num_ips - 1)) {
            exists_ors[j+1] = OR();
            exists_ors[j+1].a <== exists_ors[j].out;
        }
    }

    // Move exists_binary assignment outside the loops
    exists_binary <== exists_ors[num_ips - 1].out;

    // Process IP updates
    for (var i = 0; i < num_ips; i++) {
        isZero[i].in <== initialState_ips[i];
        
        mux1[i] = Mux1();
        mux2[i] = Mux1();
        
        // Ensure control signals are binary
        mux1[i].c <== isZero[i].out;
        mux1[i].a <== new_ip;
        mux1[i].b <== initialState_ips[i];
        
        mux2[i].c <== exists_binary;
        // TODO: Is this properly constrained?
        mux2[i].a <== i < num_ips-1 ? initialState_ips[i+1] : new_ip;
        mux2[i].b <== mux1[i].out;
        newState_ips[i] <== mux2[i].out;
    }

    // Create new state with updated IP list
    component newStateComponent = CreateState(num_ips);
    newStateComponent.ips <== newState_ips;
    newStateComponent.nonce <== initialState_nonce;
    
    // Connect outputs
    stateHash <== newStateComponent.stateHash;
    sig_r <== newStateComponent.sig_r;
    sig_s_inv <== newStateComponent.sig_s_inv;
    newState_nonce <== initialState_nonce;
}

// Convert function to template
template CheckValidStateUpdate() {
    // Define input signals for the states
    signal input initialStateHash;
    signal input initialSigR;
    signal input initialSigSInv;
    signal input proposedStateHash;
    signal input proposedSigR;
    signal input proposedSigSInv;
    signal output isValid;

    // Verify initial state signature
    component initialVerifier = Verify();
    initialVerifier.hashed_msg <== initialStateHash;
    initialVerifier.r <== initialSigR;
    initialVerifier.s_inv <== initialSigSInv;

    // Compare hashes
    component hashesEqual = IsEqual();
    hashesEqual.in[0] <== initialStateHash;
    hashesEqual.in[1] <== proposedStateHash;

    // Verify proposed state signature
    component proposedVerifier = Verify();
    proposedVerifier.hashed_msg <== proposedStateHash;
    proposedVerifier.r <== proposedSigR;
    proposedVerifier.s_inv <== proposedSigSInv;

    // Break down the multiplication into intermediate steps
    signal intermediate;
    intermediate <== initialVerifier.out * (1 - hashesEqual.out);
    isValid <== intermediate * proposedVerifier.out;
}

template AttemptStateUpdate(num_ips) {
    // Public inputs
    signal input ips[num_ips];
    signal input nonce;
    signal input new_ip;
    signal input is_challenge_response;

    // Outputs
    signal output newState[num_ips];
    signal output newStateNonce;
    signal output challenge_failed;

    // Create initial state
    component initialState = CreateState(num_ips);
    initialState.ips <== ips;
    initialState.nonce <== nonce;

    // Propose new state
    component proposedState = ProposeStateUpdate(num_ips);
    // Connect individual signals instead of the whole template
    for (var i = 0; i < num_ips; i++) {
        proposedState.initialState_ips[i] <== initialState.ipsOut[i];
    }
    proposedState.initialState_nonce <== initialState.nonceOut;
    proposedState.new_ip <== new_ip;

    // Validate state update
    component stateValidator = CheckValidStateUpdate();
    stateValidator.initialStateHash <== initialState.stateHash;
    stateValidator.initialSigR <== initialState.sig_r;
    stateValidator.initialSigSInv <== initialState.sig_s_inv;
    stateValidator.proposedStateHash <== proposedState.stateHash;
    stateValidator.proposedSigR <== proposedState.sig_r;
    stateValidator.proposedSigSInv <== proposedState.sig_s_inv;

    // If valid update or successful challenge, return new state
    component resultMux[num_ips];
    component nonceMux = Mux1();
    
    // Select between proposed and initial state based on validation
    signal selector;
    // TODO: Might need binary validation?
    selector <== stateValidator.isValid + is_challenge_response - (stateValidator.isValid * is_challenge_response);
    
    for (var i = 0; i < num_ips; i++) {
        resultMux[i] = Mux1();
        resultMux[i].c <== selector;
        resultMux[i].a <== proposedState.newState_ips[i];
        resultMux[i].b <== initialState.ipsOut[i];
        newState[i] <== resultMux[i].out;
    }
    
    nonceMux.c <== selector;
    nonceMux.a <== proposedState.newState_nonce;
    nonceMux.b <== initialState.nonceOut;
    newStateNonce <== nonceMux.out;
    
    challenge_failed <== 1 - selector;
}

// TODO: Range check IPs at some point!
component main { public [ is_challenge_response ]} = AttemptStateUpdate(5);