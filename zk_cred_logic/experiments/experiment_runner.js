// experiment_runner.js
// Usage: node experiment_runner.js <state_length> <num_runs> <output_file> <mode>
// <mode> can be 'success', 'failure', or omitted for random
// const snarkjs = require("snarkjs");
const fs = require("fs");
const { execSync } = require("child_process");
const { buildEddsa, buildBabyjub, buildPoseidon } = require("circomlibjs");

function getExample(k) {
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

    // Pad or slice to length k
    const ips_k = Array(k).fill().map((_, i) => ips[i % 5]);
    const geohashes_k = Array(k).fill().map((_, i) => geohashes[i % 5]);
    return {
        ips: ips_k,
        geohashes: geohashes_k,
        last_fingerprint,
        users_prf_seed: "1111111111",
        state_counter: "3",
        yob: ["48", "48"],
        initial_comm_rand: "1111111111111",
        new_ip: "3232235526",
        new_geohash: "458442947864549440",
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint
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
    const state_vec_string = unsigned_input.ips.concat(unsigned_input.geohashes).concat(unsigned_input.last_fingerprint.concat([unsigned_input.users_prf_seed, unsigned_input.state_counter])).concat(unsigned_input.yob);
    let state_hash = await chainedPoseidonHash(state_vec_string, poseidon);
    const comm_vec = [unsigned_input.initial_comm_rand, F_Poseidon.toObject(state_hash).toString()];
    let comm_hash = poseidon(comm_vec.map(x => poseidon.F.e(x)));
    const state_signature = eddsa.signPoseidon(prvKey, comm_hash);
    unsigned_input.initial_state_r8x = F.toObject(state_signature.R8[0]).toString();
    unsigned_input.initial_state_r8y = F.toObject(state_signature.R8[1]).toString();
    unsigned_input.initial_state_s = state_signature.S.toString();
    const response_vec_string = [unsigned_input.new_ip, unsigned_input.new_geohash, unsigned_input.new_rappor_nonce];
    let response_hash = poseidon(response_vec_string.map(x => poseidon.F.e(x)));
    const response_signature = eddsa.signPoseidon(prvKey, response_hash);
    unsigned_input.new_user_info_r8x = F.toObject(response_signature.R8[0]).toString();
    unsigned_input.new_user_info_r8y = F.toObject(response_signature.R8[1]).toString();
    unsigned_input.new_user_info_s = response_signature.S.toString();
    return unsigned_input;
}

async function main() {
    const k = parseInt(process.argv[2]);
    const N = parseInt(process.argv[3]);
    const outputFile = process.argv[4] || `new_results_no_ldp/experiment_results_k${k}_N${N}.json`;

    // Create output directory if it doesn't exist
    const outputDir = outputFile.substring(0, outputFile.lastIndexOf('/'));
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    if (!k || !N) {
        console.error("Usage: node experiment_runner.js <state_length> <num_runs> <output_file>");
        // console.error("Note: Uses pre-generated inputs from k${k}/inputs_k${k}_N100_success.json");
        process.exit(1);
    }
    const results = [];
    // Load the pre-generated inputs

    for (let i = 0; i < N; i++) {

        // Use the pre-generated input for this run
        let input_obj = getExample(k);

        // Sign the input (this adds the cryptographic signatures)
        input_obj = await sign_circom_inputs(input_obj);
        input_obj = cleanInputs(input_obj); // Ensure all values are strings or numbers

        // Create proofs subdirectory if it doesn't exist
        const proofsDir = `k${k}/proofs`;
        if (!fs.existsSync(proofsDir)) {
            fs.mkdirSync(proofsDir, { recursive: true });
        }

        // Run Rapidsnark prover with the existing witness file
        const proofFile = `${proofsDir}/proof_${i}.json`;
        const publicFile = `${proofsDir}/public_${i}.json`;

        const startProve = process.hrtime.bigint();
        let proveError = null;
        try {
            // Use the pre-generated witness file directly with Rapidsnark
            const witnessFile = `k${k}/witness.wtns`;

            const output = execSync(`./prover k${k}/state_0001.zkey ${witnessFile} ${proofFile} ${publicFile}`, {
                encoding: 'utf8',
                cwd: __dirname  // Run from the experiments directory
            });

            // Debug: log the raw output from Rapidsnark
            console.log(`Rapidsnark output for run ${i}: ${output}`);

            // Read the generated proof and public files
            // try {
            //     const proofContent = fs.readFileSync(proofFile, 'utf8');
            //     const publicContent = fs.readFileSync(publicFile, 'utf8');

            //     // Debug: log the first few characters to see what we're getting
            //     // console.log(`Proof file ${i} starts with: ${proofContent.substring(0, 100)}...`);
            //     // console.log(`Public file ${i} starts with: ${publicContent.substring(0, 100)}...`);

            //     // Clean the content by removing null bytes and trimming whitespace
            //     const cleanProofContent = proofContent.replace(/\0/g, '').trim();
            //     const cleanPublicContent = publicContent.replace(/\0/g, '').trim();

            //     proof = JSON.parse(cleanProofContent);
            //     publicSignals = JSON.parse(cleanPublicContent);

            // } catch (parseError) {
            //     proveError = `JSON parsing failed: ${parseError.message}. File contents may be malformed.`;
            //     // Keep the files for debugging if parsing fails
            //     console.log(`Keeping malformed files for debugging: ${proofFile}, ${publicFile}`);
            // }
        } catch (e) {
            proveError = `Rapidsnark failed: ${e.message}`;
        }
        const endProve = process.hrtime.bigint();
        const proveTimeMs = Number(endProve - startProve) / 1e6;
        let verifyTimeMs = null, res = null, verifyError = null;
        if (!proveError) {
            // const vKey = JSON.parse(fs.readFileSync(`k${k}/verification_key.json`));
            const startVerify = process.hrtime.bigint();
            try {
                // res = await snarkjs.groth16.verify(vKey, publicSignals, proof);
                const output = execSync(`./verifier k${k}/verification_key.json ${publicFile} ${proofFile}`, {
                    encoding: 'utf8',
                    cwd: __dirname  // Run from the experiments directory
                });
                res = true
                // console.log(`Verifier output for run ${i}: ${output}`);
            } catch (e) {
                verifyError = e.toString();
                res = false
                // console.log(`Verifier error for run ${i}: ${verifyError}`);
            }
            const endVerify = process.hrtime.bigint();
            verifyTimeMs = Number(endVerify - startVerify) / 1e6;
            // Clean up temporary files
            // fs.unlinkSync(proofFile);
            // fs.unlinkSync(publicFile);
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