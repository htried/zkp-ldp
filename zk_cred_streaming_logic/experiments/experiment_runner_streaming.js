// experiment_runner_streaming.js
// Usage: node experiment_runner_streaming.js <num_runs> <output_file>
const snarkjs = require("snarkjs");
const fs = require("fs");
const { buildEddsa, buildBabyjub, buildPoseidon } = require("circomlibjs");

const prvKeyHex = "0001020304050607080900010203040506070809000102030405060708090001";

async function getStreamingExample() {
    const poseidon = await buildPoseidon();
    const eddsa = await buildEddsa();
    const babyJub = await buildBabyjub();
    const F = babyJub.F;
    const F_Poseidon = poseidon.F;
    const prvKey = Buffer.from(prvKeyHex, "hex");
    // Example values (replace with realistic test data as needed)
    const fp = [
        "000000000000000000000000000000000000000000000000000000000000000000000000000",
        "11111111111111111111111111111111111111111111111111111111111111111111111111"
    ];
    let last_fingerprint = fp;
    let new_fingerprint = fp;
    let geohash_sum = BigInt(458442947864549440) * BigInt(3);
    let state_counter = BigInt(3);
    let avg_geohash = geohash_sum / state_counter;
    let users_prf_seed = "1111111111";
    let state_comm_rand = "1111111111111";
    let new_geohash = BigInt("458442947864549440");
    let next_geohash_sum = geohash_sum + new_geohash;
    let next_state_counter = state_counter + BigInt(1);
    let next_avg_geohash = next_geohash_sum / next_state_counter;
    // --- State hash and commitment (as in circuit) ---
    // state_hash_inputs: [geohash_sum, state_counter, avg_geohash, last_fingerprint[0], last_fingerprint[1], users_prf_seed]
    const state_hash_inputs = [
        geohash_sum.toString(),
        state_counter.toString(),
        avg_geohash.toString(),
        last_fingerprint[0],
        last_fingerprint[1],
        users_prf_seed
    ];
    // Poseidon(6) for state hash
    const state_hash = poseidon(state_hash_inputs.map(x => poseidon.F.e(x)));
    // Commitment: Poseidon([state_comm_rand, state_hash])
    const comm_vec = [state_comm_rand, F_Poseidon.toObject(state_hash).toString()];
    const comm_hash = poseidon(comm_vec.map(x => poseidon.F.e(x)));
    // EdDSA signature on commitment
    const state_signature = eddsa.signPoseidon(prvKey, comm_hash);
    // --- Server response hash and signature ---
    // response_hasher = Poseidon([new_geohash, new_rappor_nonce])
    const new_rappor_nonce = "1";
    const response_vec = [new_geohash.toString(), new_rappor_nonce];
    const response_hash = poseidon(response_vec.map(x => poseidon.F.e(x)));
    const response_signature = eddsa.signPoseidon(prvKey, response_hash);
    return {
        geohash_sum: geohash_sum.toString(),
        state_counter: state_counter.toString(),
        avg_geohash: avg_geohash.toString(),
        last_fingerprint,
        users_prf_seed,
        initial_state_r8x: F.toObject(state_signature.R8[0]).toString(),
        initial_state_r8y: F.toObject(state_signature.R8[1]).toString(),
        initial_state_s: state_signature.S.toString(),
        initial_comm_rand: state_comm_rand,
        new_geohash: new_geohash.toString(),
        new_rappor_nonce: new_rappor_nonce,
        new_user_info_r8x: F.toObject(response_signature.R8[0]).toString(),
        new_user_info_r8y: F.toObject(response_signature.R8[1]).toString(),
        new_user_info_s: response_signature.S.toString(),
        state_comm_randomness: state_comm_rand,
        new_fingerprint,
        next_avg_geohash: next_avg_geohash.toString()
    };
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

async function main() {
    const N = parseInt(process.argv[2]) || 100;
    const outputFile = process.argv[3] || `experiment_results_streaming_N${N}.json`;
    const results = [];
    for (let i = 0; i < N; i++) {
        let input_obj = await getStreamingExample();
        input_obj = cleanInputs(input_obj);
        const startProve = process.hrtime.bigint();
        let proof, publicSignals, proveError = null;
        try {
            ({ proof, publicSignals } = await snarkjs.groth16.fullProve(
                input_obj,
                `../state_streaming_js/state_streaming.wasm`,
                `../state_streaming_0001.zkey`
            ));
        } catch (e) {
            proveError = e.toString();
        }
        const endProve = process.hrtime.bigint();
        const proveTimeMs = Number(endProve - startProve) / 1e6;
        let verifyTimeMs = null, res = null, verifyError = null;
        if (!proveError) {
            const vKey = JSON.parse(fs.readFileSync(`../verification_key.json`));
            const startVerify = process.hrtime.bigint();
            try {
                res = await snarkjs.groth16.verify(vKey, publicSignals, proof);
            } catch (e) {
                verifyError = e.toString();
            }
            const endVerify = process.hrtime.bigint();
            verifyTimeMs = Number(endVerify - startVerify) / 1e6;
        }
        results.push({
            run: i,
            proveTimeMs,
            verifyTimeMs,
            verified: res,
            proveError,
            verifyError
        });
        console.log(`Run ${i}: Prove ${proveTimeMs.toFixed(2)} ms${proveError ? ", ProveError: " + proveError : ""}, Verify ${verifyTimeMs !== null ? verifyTimeMs.toFixed(2) : "-"} ms, Verified: ${res}`);
    }
    fs.writeFileSync(`${outputFile}`, JSON.stringify(results, null, 2));
    console.log(`Results written to ${outputFile}`);
    process.exit(0);
}

main(); 