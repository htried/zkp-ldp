const fs = require("fs");
const { execSync } = require("child_process");

async function run() {
    const N = 100;
    const outputFile = `experiment_results_cold_start_N${N}.json`;
    const results = [];

    for (let i = 0; i < N; i++) {
        const start = performance.now();
        let proveTime = 0;
        let verifyTime = 0;
        let totalTime = 0;
        let success = false;
        let error = null;

        try {
            // Run Rapidsnark prover directly with existing input.json
            const proveStart = performance.now();
            const output = execSync(`/Users/haltriedman/code/zkp-ldp/zk_cred_logic/experiments/prover cold_start_0001.zkey witness.wtns proof.json public.json`, {
                encoding: 'utf8',
                cwd: __dirname
            });
            const proveEnd = performance.now();
            proveTime = proveEnd - proveStart;

            // Verify using Rapidsnark verifier
            const verifyStart = performance.now();
            const verifyOutput = execSync(`/Users/haltriedman/code/zkp-ldp/zk_cred_logic/experiments/verifier verification_key.json public.json proof.json`, {
                encoding: 'utf8',
                cwd: __dirname
            });
            const verifyEnd = performance.now();
            verifyTime = verifyEnd - verifyStart;

            const end = performance.now();
            totalTime = end - start;
            success = true;

        } catch (e) {
            const end = performance.now();
            totalTime = end - start;
            error = e.message;
        }

        results.push({
            run: i,
            proveTimeMs: proveTime,
            verifyTimeMs: verifyTime,
            totalTimeMs: totalTime,
            success: success,
            error: error
        });

        console.log(`Run ${i}: Prove ${proveTime.toFixed(2)} ms, Verify ${verifyTime.toFixed(2)} ms, Total ${totalTime.toFixed(2)} ms, Success: ${success}`);
    }

    // Write results to JSON file
    fs.writeFileSync(outputFile, JSON.stringify(results, null, 2));
    console.log(`Results written to ${outputFile}`);
}

run().then(() => {
    process.exit(0);
});