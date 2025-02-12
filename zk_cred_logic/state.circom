pragma circom 2.2.0;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/gates.circom";
include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/babyjub.circom";
include "circomlib/circuits/pedersen.circom";

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
// Arbitrary length MultiEqual component
template MultiEqual(n) {
    signal input in[2][n];
    signal output out;

    component equalityChecks[n];
    signal temp[n];
    
    for (var i = 0; i < n; i++) {
        equalityChecks[i] = IsEqual();
        equalityChecks[i].in[0] <== in[0][i];
        equalityChecks[i].in[1] <== in[1][i];
        temp[i] <== equalityChecks[i].out;
    }
    component and = MultiAND(n);
    and.in <== temp;
    out <== and.out;
}

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

// ============== IP ADDRESS PARSING FUNCTIONS =================
// Convert IPv4 string to array of 4 numbers
template IPv4StringToNumbers() {
    signal input ipString[15];  // Max length for IPv4 (xxx.xxx.xxx.xxx)
    signal output ipNumbers[4];

    var currentNum = 0;
    var currentOctet = 0;
    var nums[4];  // Temporary array to store computed values
    var foundStart = 0;
    
    // Process each character
    for (var i = 0; i < 15; i++) {
        if (ipString[i] == 46) { // Period character
            nums[currentOctet] = currentNum;
            currentNum = 0;
            currentOctet++;
            foundStart = 1;
        } else if (ipString[i] >= 49 && ipString[i] <= 57) { // Digits 1-9
            currentNum = currentNum * 10 + (ipString[i] - 48);
            foundStart = 1;
        } else if (ipString[i] == 48) { // Handle 0
            if (foundStart == 1) { // Only process 0 if we've found start
                currentNum = currentNum * 10;
            }
        }
        
        // Handle last octet
        if (i == 14) {
            nums[currentOctet] = currentNum;
        }
    }

    // Assign all numbers at once
    for (var i = 0; i < 4; i++) {
        ipNumbers[i] <-- nums[i];
    }

    // Ensure each number is within valid range (0-255)
    for (var i = 0; i < 4; i++) {
        // log(ipNumbers[i]);
        assert(ipNumbers[i] >= 0 && ipNumbers[i] <= 255);
    }
}

// Convert numbers to bits for IPv4
template IPNumbersToBits() {
    signal input ipNumbers[4];
    signal output ipBits[32];  // 4 numbers * 8 bits each
    component num2Bits[4];

    for (var i = 0; i < 4; i++) {
        num2Bits[i] = Num2Bits(8);
        num2Bits[i].in <== ipNumbers[i];
        for (var j = 0; j < 8; j++) {
            ipBits[i*8 + j] <== num2Bits[i].out[j];
        }
    }
}

// Simplified IP string to bits conversion (IPv4 only)
template IPStringToBits() {
    signal input ipString[15];
    signal output ipBits[32];

    component ipv4ToNumbers = IPv4StringToNumbers();
    component ipv4ToBits = IPNumbersToBits();

    ipv4ToNumbers.ipString <== ipString;
    ipv4ToBits.ipNumbers <== ipv4ToNumbers.ipNumbers;
    ipBits <== ipv4ToBits.ipBits;
}

// ============== STATE MANAGEMENT FUNCTIONS =================

// Create a state with a given number of IP addresses
//  This state will be hashed and signed to ensure integrity and prevent tampering
template CreateState(num_ips) {
    signal input ipStrings[num_ips][15];
    signal input nonce;
    
    signal output ipStringsOut[num_ips][15];
    signal output nonceOut;
    signal output ipBits[num_ips * 32]; // 32 bits for each IP address
    signal output nonceBits[32]; // 32 bits for nonce
    signal output stateHash; // Hash of ipBits and nonce
    signal output sig_r;
    signal output sig_s_inv;

    ipStringsOut <== ipStrings;
    nonceOut <== nonce;

    // Convert IP strings to bits
    component ipConverters[num_ips];
    component ipsAs32BitNumbers[num_ips];
    for (var i = 0; i < num_ips; i++) {
        ipConverters[i] = IPStringToBits();
        ipConverters[i].ipString <== ipStrings[i];
        ipsAs32BitNumbers[i] = Bits2Num(32);
        ipsAs32BitNumbers[i].in <== ipConverters[i].ipBits;
        for (var j = 0; j < 32; j++) {
            ipBits[i * 32 + j] <== ipConverters[i].ipBits[j];
        }
    }

    // Hash ipBits and nonce together
    var len = num_ips + 1;
    
    component hasher = Poseidon(len);

    // Combine ipBits and nonceBits into hash input
    for (var i = 0; i < num_ips; i++) {
        hasher.inputs[i] <== ipsAs32BitNumbers[i].out;
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

    // Now use the template's output
    verifier.out === 1;
}

// Propose a new state update
template ProposeStateUpdate(num_ips) {
    // Input signals
    signal input initialState_ipStrings[num_ips][15];
    signal input initialState_nonce;
    signal input new_ip[15];
    
    // Output signals
    signal output newState_ipStrings[num_ips][15];
    signal output newState_nonce;
    signal output stateHash;
    signal output sig_r;
    signal output sig_s_inv;

    signal exists_binary;

    // Pre-declare components
    component isZero[num_ips];
    component mux1[num_ips][15];
    component mux2[num_ips][15];
    component ipEqual[num_ips];

    // Initialize components and check for IP existence first
    component exists_ors[num_ips];
    exists_ors[0] = OR();
    exists_ors[0].a <== 0;
    for (var j = 0; j < num_ips; j++) {
        isZero[j] = IsZero();
        ipEqual[j] = MultiEqual(15);
        
        // Check IP equality once
        for (var k = 0; k < 15; k++) {
            ipEqual[j].in[0][k] <== initialState_ipStrings[j][k];
            ipEqual[j].in[1][k] <== new_ip[k];
        }
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
        isZero[i].in <== initialState_ipStrings[i][0];
        
        for (var j = 0; j < 15; j++) {
            mux1[i][j] = Mux1();
            mux2[i][j] = Mux1();
            
            // Ensure control signals are binary
            mux1[i][j].c <== isZero[i].out;
            mux1[i][j].a <== new_ip[j];
            mux1[i][j].b <== initialState_ipStrings[i][j];
            
            mux2[i][j].c <== exists_binary;
            mux2[i][j].a <== i < num_ips-1 ? initialState_ipStrings[i+1][j] : new_ip[j];
            mux2[i][j].b <== mux1[i][j].out;
            newState_ipStrings[i][j] <== mux2[i][j].out;
        }
    }

    // Create new state with updated IP list
    component newStateComponent = CreateState(num_ips);
    newStateComponent.ipStrings <== newState_ipStrings;
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
    signal input ipStrings[num_ips][15];
    signal input nonce;
    signal input new_ip[15];
    signal input is_challenge_response;

    // Outputs
    signal output newState[num_ips][15];
    signal output newStateNonce;
    signal output challenge_failed;

    // Create initial state
    component initialState = CreateState(num_ips);
    initialState.ipStrings <== ipStrings;
    initialState.nonce <== nonce;

    // Propose new state
    component proposedState = ProposeStateUpdate(num_ips);
    // Connect individual signals instead of the whole template
    for (var i = 0; i < num_ips; i++) {
        for (var j = 0; j < 15; j++) {
            proposedState.initialState_ipStrings[i][j] <== initialState.ipStringsOut[i][j];
        }
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
    component resultMux[num_ips][15];
    component nonceMux = Mux1();
    
    // Select between proposed and initial state based on validation
    signal selector;
    selector <== stateValidator.isValid + is_challenge_response - (stateValidator.isValid * is_challenge_response);
    
    for (var i = 0; i < num_ips; i++) {
        for (var j = 0; j < 15; j++) {
            resultMux[i][j] = Mux1();
            resultMux[i][j].c <== selector;
            resultMux[i][j].a <== proposedState.newState_ipStrings[i][j];
            resultMux[i][j].b <== initialState.ipStringsOut[i][j];
            newState[i][j] <== resultMux[i][j].out;
        }
    }
    
    nonceMux.c <== selector;
    nonceMux.a <== proposedState.newState_nonce;
    nonceMux.b <== initialState.nonceOut;
    newStateNonce <== nonceMux.out;
    
    challenge_failed <== 1 - selector;
}

component main { public [ is_challenge_response ]} = AttemptStateUpdate(5);