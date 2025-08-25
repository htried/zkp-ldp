// generate_inputs.js
// Generate and sign inputs for browser testing
const fs = require("fs");
const { buildEddsa, buildBabyjub, buildPoseidon } = require("circomlibjs");

function getSuccessExample(k) {
    const ips = [
        "3232235521", "3232235522", "3232235523", "3232235524", "3232235525"
    ];
    const geohashes = [
        "458442933798745700", "458442933798745700", "458442933798745700", "458442933798745700", "458442933798745700"
    ];
    const fp = [
        "000000000000000000000000000000000000000000000000000000000000000000000000000",
        "11111111111111111111111111111111111111111111111111111111111111111111111111"
    ];
    const last_fingerprint = fp;
    const new_fingerprint = fp;

    // Keep IPs and geohashes constant at 5
    const ips_k = ips;
    const geohashes_k = geohashes;

    // Create attribution history that will return true for the chain search
    // The circom file searches for [15, 16, 17, 18] in sequence
    // We'll create a history that contains this sequence
    // This will make the chain search in the circuit return true (match found)
    const attribution_history = [];
    for (let i = 0; i < k; i++) {
        if (i < 4) {
            // Place the search sequence [15, 16, 17, 18] at the beginning
            // This matches the search_chain_values in the circom file
            attribution_history.push((15 + i).toString());
        } else {
            // Fill the rest with other values
            attribution_history.push((20 + i).toString());
        }
    }

    return {
        ips: ips_k,
        geohashes: geohashes_k,
        last_fingerprint,
        yob: ["48", "48"], // ASCII "00" = year 2000 (48 is ASCII for '0')
        attribution_history,
        users_prf_seed: "1111111111",
        state_counter: "3",
        initial_comm_rand: "1111111111111",
        new_ip: "3232235526",
        new_geohash: "458442947864549440",
        new_attribution_value: "25", // New attribution value to add
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint
    };
}

function getFailureExample(k) {
    const ex = getSuccessExample(k);
    ex.new_fingerprint = [
        "111111111111111111111111111111111111111111111111111111111111111111111111111",
        "00000000000000000000000000000000000000000000000000000000000000000000000000"
    ];
    return ex;
}

function cleanInputs(obj) {
    if (Array.isArray(obj)) {
        return obj.map(cleanInputs);
    } else if (typeof obj === 'bigint') {
        return obj.toString();
    } else if (typeof obj === 'object' && obj !== null) {
        const newObj = {};
        for (const k in obj) {
            newObj[k] = cleanInputs(obj[k]);
        }
        return newObj;
    } else {
        return obj;
    }
}

// Helper: Chained Poseidon Hash for arrays > 16
async function chainedPoseidonHash(arr, poseidon) {
    let F = poseidon.F;
    // Normalize all inputs to strings, then to field elements
    let normArr = arr.map(x => (typeof x === 'bigint' ? x.toString() : x)).map(x => F.e(x));
    let numBlocks = Math.floor(normArr.length / 15) + (normArr.length % 15 !== 0 ? 1 : 0);
    let prevHash = F.e(0);
    for (let b = 0; b < numBlocks; b++) {
        let start = b * 15;
        let block = normArr.slice(start, start + 15);
        while (block.length < 15) block.push(F.e(0));
        let inputs = [...block, prevHash];
        prevHash = poseidon(inputs);
    }
    return prevHash;
}

async function sign_circom_inputs(unsigned_input) {
    const poseidon = await buildPoseidon();
    const F_Poseidon = poseidon.F;
    const eddsa = await buildEddsa();
    const babyJub = await buildBabyjub();
    const F = babyJub.F;
    const prvKey = Buffer.from("0001020304050607080900010203040506070809000102030405060708090001", "hex");
    const pubKey = eddsa.prv2pub(prvKey);

    // Include yob and attribution_history in the state hash calculation
    const state_vec_string = unsigned_input.ips.concat(unsigned_input.geohashes).concat(unsigned_input.last_fingerprint).concat(unsigned_input.yob).concat(unsigned_input.attribution_history).concat([unsigned_input.users_prf_seed, unsigned_input.state_counter]);
    let state_hash = await chainedPoseidonHash(state_vec_string, poseidon);
    const comm_vec = [unsigned_input.initial_comm_rand, F_Poseidon.toObject(state_hash).toString()];
    let comm_hash = poseidon(comm_vec.map(x => poseidon.F.e(x)));
    const state_signature = eddsa.signPoseidon(prvKey, comm_hash);
    unsigned_input.initial_state_r8x = F.toObject(state_signature.R8[0]).toString();
    unsigned_input.initial_state_r8y = F.toObject(state_signature.R8[1]).toString();
    unsigned_input.initial_state_s = state_signature.S.toString();
    const response_vec_string = [unsigned_input.new_ip, unsigned_input.new_geohash, unsigned_input.new_rappor_nonce, unsigned_input.new_attribution_value];
    let response_hash = poseidon(response_vec_string.map(x => poseidon.F.e(x)));
    const response_signature = eddsa.signPoseidon(prvKey, response_hash);
    unsigned_input.new_user_info_r8x = F.toObject(response_signature.R8[0]).toString();
    unsigned_input.new_user_info_r8y = F.toObject(response_signature.R8[1]).toString();
    unsigned_input.new_user_info_s = response_signature.S.toString();
    return unsigned_input;
}

async function main() {
    // const k = parseInt(process.argv[2]) || 5;
    const mode = process.argv[3] || "success";

    const ks = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]; // skip 1 because it's the same as single logic

    for (const k of ks) {
        console.log(`Generating inputs for k=${k}...`);
        let input_obj;
        if (mode === "success") {
            input_obj = getSuccessExample(k);
        } else if (mode === "failure") {
            input_obj = getFailureExample(k);
        } else {
            console.error("Invalid mode");
            process.exit(1);
        }

        input_obj = await sign_circom_inputs(input_obj);
        input_obj = cleanInputs(input_obj);

        const singleFile = `k${k}/input.json`;
        fs.writeFileSync(singleFile, JSON.stringify(input_obj, null, 2));
    }
}

main().catch(console.error);
