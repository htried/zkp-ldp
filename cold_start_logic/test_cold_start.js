const snarkjs = require("snarkjs");
const fs = require("fs");
const { buildEddsa, buildBabyjub, buildPoseidon } = require("circomlibjs");

// List of test cases. Values that should be cryptographically random
// but aren't relevant for correctness tests are set to strings of 1's.
const test_cases = [
    // I only see a need for one tet case at the moment.
    {
        fingerprint: [
            "996452246304932491187838448288367965371837357284206925883546866701294631124",
            "15569566348514570174809975754505749458934958707565733216930419792207728611"
          ], 
        users_prf_seed: "1111111111",  
        initial_comm_rand: "1111111111111", 
    }
];

async function run() {
    for (input_obj of test_cases) {
        console.log(JSON.stringify(input_obj, null, 2));

        const { proof, publicSignals } = await snarkjs.groth16.fullProve(input_obj, "cold_start_js/cold_start.wasm", "cold_start_0001.zkey");

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