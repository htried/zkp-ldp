const snarkjs = require("snarkjs");
const fs = require("fs");
const { buildEddsa, buildBabyjub, buildPoseidon } = require("circomlibjs");

// Realistic test data for fingerprints:
// Fingerprint 1 Hash as Felts: [
//     "996452246304932491187838448288367965371837357284206925883546866701294631124",
//     "15569566348514570174809975754505749458934958707565733216930419792207728611"
//   ]
// Fingerprint 2 Hash as Felts: [
// "1568465034027929785865490850681301670064582328743610951506161259038211815489",
// "929132963323219179650796614922269618698430854086935827675546144734293384929"
// ]
// Should have a similarity score of 0.71875

// Realistic test data for geohashes:
// Original geohash field element: 3856082809388864
// Northwest neighbor with offset 20,000,000: 4267277943437888
// West neighbor with offset 20,000,000: 3913515921751872
// South neighbor with offset 20,000,000: 3781893096766208

// List of test cases. Values that should be cryptographically random
// but aren't relevant for correctness tests are set to strings of 1's.
const test_cases = [
    // "Cold start" test case. A different circuit would be used for registration to construct an empty state.
    {ips: ["0","0","0","0","0"], 
        geohashes: ["0","0","0","0","0"], 
        last_fingerprint: [
            "996452246304932491187838448288367965371837357284206925883546866701294631124",
            "15569566348514570174809975754505749458934958707565733216930419792207728611"
          ], 
        users_prf_seed: "1111111111", 
        state_counter: "0", 
        initial_comm_rand: "1111111111111", 
        new_ip: "3232235526", 
        new_geohash: "3856082809388864",
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint: [
            "1568465034027929785865490850681301670064582328743610951506161259038211815489",
            "929132963323219179650796614922269618698430854086935827675546144734293384929"
            ] },
    // Adding an IP that already exists to the list.
    {ips: ["3232235526","0","0","0","0"], 
        geohashes: ["3856082809388864","0","0","0","0"], 
        last_fingerprint: [
            "996452246304932491187838448288367965371837357284206925883546866701294631124",
            "15569566348514570174809975754505749458934958707565733216930419792207728611"
          ], 
        users_prf_seed: "1111111111", 
        state_counter: "0", 
        initial_comm_rand: "1111111111111", 
        new_ip: "3232235526", 
        new_geohash: "3856082809388864",
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint: [
            "1568465034027929785865490850681301670064582328743610951506161259038211815489",
            "929132963323219179650796614922269618698430854086935827675546144734293384929"
            ] },
    // Adding a new IP to a non empty list
    {ips: ["3232235526","0","0","0","0"], 
        geohashes: ["458443319826090800","0","0","0","0"], 
        last_fingerprint: [
            "996452246304932491187838448288367965371837357284206925883546866701294631124",
            "15569566348514570174809975754505749458934958707565733216930419792207728611"
          ], 
        users_prf_seed: "1111111111", 
        state_counter: "0", 
        initial_comm_rand: "1111111111111", 
        new_ip: "3232235521", 
        new_geohash: "458442982927086700",
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint: [
            "1568465034027929785865490850681301670064582328743610951506161259038211815489",
            "929132963323219179650796614922269618698430854086935827675546144734293384929"
            ] },
    // Adding an IP that already exists to a list that is full.
    {ips: ["3232235521","3232235522","3232235523","3232235524","3232235525"], 
        geohashes: ["3856082809388864","3856082809388864","3856082809388864","3856082809388864","3856082809388864"], 
        last_fingerprint: [
            "996452246304932491187838448288367965371837357284206925883546866701294631124",
            "15569566348514570174809975754505749458934958707565733216930419792207728611"
          ], 
        users_prf_seed: "1111111111", 
        state_counter: "3", 
        initial_comm_rand: "1111111111111", 
        new_ip: "3232235525", 
        new_geohash: "3856082809388864",
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint: [
            "1568465034027929785865490850681301670064582328743610951506161259038211815489",
            "929132963323219179650796614922269618698430854086935827675546144734293384929"
            ] },
    // Adding a new IP when the list is full, also checks geohash neighbor logic.
    {ips: ["3232235521","3232235522","3232235523","3232235524","3232235525"], 
        geohashes: ["458442933798745700","458442933798745700","458442933798745700","458442933798745700","458442933798745700"], 
        last_fingerprint: [
            "996452246304932491187838448288367965371837357284206925883546866701294631124",
            "15569566348514570174809975754505749458934958707565733216930419792207728611"
          ], 
        users_prf_seed: "1111111111", 
        state_counter: "3", 
        initial_comm_rand: "1111111111111", 
        new_ip: "3232235526", 
        new_geohash: "458442947864549440",
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint: [
            "1568465034027929785865490850681301670064582328743610951506161259038211815489",
            "929132963323219179650796614922269618698430854086935827675546144734293384929"
            ] }
];

// We need to generate signatures on the server response and the
// initial state to make these valid inputs for circom.
async function sign_circom_inputs(unsigned_input) {
    // Initialize the different crypto libraries.
    const poseidon = await buildPoseidon();
    const F_Poseidon = poseidon.F;

    const eddsa = await buildEddsa();
    const babyJub = await buildBabyjub();
    const F = babyJub.F;

    // Define private key (32 bytes).
    // Obviously this would be a better kept secret in a full implementation.
    const prvKey = Buffer.from("0001020304050607080900010203040506070809000102030405060708090001", "hex");
    // Generate public key
    const pubKey = eddsa.prv2pub(prvKey);

    const state_vec_string = unsigned_input.ips.concat(unsigned_input.geohashes).concat(unsigned_input.last_fingerprint.concat([unsigned_input.users_prf_seed, unsigned_input.state_counter]));
    const state_hash = poseidon(state_vec_string);

    const comm_vec = [unsigned_input.initial_comm_rand, F_Poseidon.toObject(state_hash).toString()];
    const comm_hash = poseidon(comm_vec);
    const state_signature = eddsa.signPoseidon(prvKey, comm_hash);

    unsigned_input.initial_state_r8x = F.toObject(state_signature.R8[0]).toString();
    unsigned_input.initial_state_r8y = F.toObject(state_signature.R8[1]).toString();
    unsigned_input.initial_state_s = state_signature.S.toString();

    const response_vec_string = [unsigned_input.new_ip, unsigned_input.new_geohash, unsigned_input.new_rappor_nonce];
    const response_hash = poseidon(response_vec_string);

    const response_signature = eddsa.signPoseidon(prvKey, response_hash);

    unsigned_input.new_user_info_r8x = F.toObject(response_signature.R8[0]).toString();;
    unsigned_input.new_user_info_r8y = F.toObject(response_signature.R8[1]).toString();
    unsigned_input.new_user_info_s = response_signature.S.toString();

    return unsigned_input;
}

async function run() {
    for (unsigned_input_obj of test_cases) {
        var input_obj = await sign_circom_inputs(unsigned_input_obj);

        console.log(JSON.stringify(input_obj, null, 2));

        const { proof, publicSignals } = await snarkjs.groth16.fullProve(input_obj, "state_js/state.wasm", "state_0001.zkey");

        console.log("Proof: ");
        console.log(JSON.stringify(proof, null, 1));

        const vKey = JSON.parse(fs.readFileSync("verification_key.json"));

        const res = await snarkjs.groth16.verify(vKey, publicSignals, proof);

        if (res === true) {
            console.log("Verification OK");
        } else {
            console.log("Invalid proof");
        }
    }
}

run().then(() => {
    process.exit(0);
});