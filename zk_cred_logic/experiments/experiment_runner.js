// experiment_runner.js
// Usage: node experiment_runner.js <state_length> <num_runs> <output_file> <mode>
// <mode> can be 'success', 'failure', or omitted for random
// const snarkjs = require("snarkjs");
const fs = require("fs");
const { execSync } = require("child_process");

async function main() {
    const k = parseInt(process.argv[2]);
    const N = parseInt(process.argv[3]);
    const outputFile = process.argv[4] || `../../results/experiment_results_k${k}_N${N}.json`;

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

            const output = execSync(`../../prove_verify/prover k${k}/state_0001.zkey ${witnessFile} ${proofFile} ${publicFile}`, {
                encoding: 'utf8',
                cwd: __dirname  // Run from the experiments directory
            });

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
                const output = execSync(`../../prove_verify/verifier k${k}/verification_key.json ${publicFile} ${proofFile}`, {
                    encoding: 'utf8',
                    cwd: __dirname  // Run from the experiments directory
                });
                res = true
            } catch (e) {
                verifyError = e.toString();
                res = false
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