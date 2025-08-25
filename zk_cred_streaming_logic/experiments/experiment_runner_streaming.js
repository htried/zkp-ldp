// experiment_runner_streaming.js
// Usage: node experiment_runner_streaming.js <num_runs> <output_file>
const fs = require("fs");
const { execSync } = require("child_process");

async function main() {
    const N = parseInt(process.argv[2]) || 100;
    const outputFile = process.argv[3] || `../../results/experiment_results_streaming_N${N}.json`;
    const results = [];
    // Create proofs subdirectory if it doesn't exist
    const proofsDir = "proofs";
    if (!fs.existsSync(proofsDir)) {
        fs.mkdirSync(proofsDir, { recursive: true });
    }

    for (let i = 0; i < N; i++) {
        const startProve = process.hrtime.bigint();
        let proveError = null;

        let verifyStart, verifyEnd;
        try {
            // Run Rapidsnark prover with existing witness file
            const output = execSync(`../../prove_verify/prover ../state_streaming_0001.zkey witness.wtns proof.json public.json`, {
                encoding: 'utf8',
                cwd: __dirname
            });

            // Now verify using Rapidsnark verifier
            verifyStart = process.hrtime.bigint();
            try {
                const verifyOutput = execSync(`../../prove_verify/verifier ../verification_key.json public.json proof.json`, {
                    encoding: 'utf8',
                    cwd: __dirname
                });
                verifyEnd = process.hrtime.bigint();

                // Clean up temporary files
                fs.unlinkSync("proof.json");
                fs.unlinkSync("public.json");

            } catch (verifyErr) {
                proveError = `Verification failed: ${verifyErr.message}`;
            }

        } catch (e) {
            proveError = `Rapidsnark failed: ${e.message}`;
        }

        const endProve = process.hrtime.bigint();
        const proveTimeMs = Number(endProve - startProve) / 1e6;

        // Calculate verification time
        const verifyTimeMs = (verifyStart && verifyEnd) ? Number(verifyEnd - verifyStart) / 1e6 : null;
        const res = !proveError; // Success if no proving error
        const verifyError = null;

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