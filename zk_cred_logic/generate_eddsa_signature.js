const { buildEddsa, buildBabyjub, buildPoseidon } = require("circomlibjs");

async function main() {
    const args = process.argv.slice(2);
    if (args.length === 0) {
        console.error("Please provide a JSON array of integers as a command-line argument.");
        process.exit(1);
    }

    var inputArray = [];
    try {
        inputArray = JSON.parse(args[0]);
    } catch (error) {
        console.error("Invalid input. Please provide a valid JSON array of integers.");
        process.exit(1);
    }

    // Ensure input is an array of integers
    if (!Array.isArray(inputArray) || !inputArray.every(Number.isInteger)) {
        throw new Error("Input must be an array of integers");
    }

    const poseidon = await buildPoseidon();
    const F_Poseidon = poseidon.F;
    
    // Hash the input
    const hash = poseidon(inputArray);
    console.log(F_Poseidon.toObject(hash).toString());

    // Initialize EdDSA and BabyJubJub
    const eddsa = await buildEddsa();
    const babyJub = await buildBabyjub();
    const F = babyJub.F;

    // Define message
    // const msg = F.e(1234);
    
    // Define private key (32 bytes)
    const prvKey = Buffer.from("0001020304050607080900010203040506070809000102030405060708090001", "hex");

    // Generate public key
    const pubKey = eddsa.prv2pub(prvKey);
    // console.log("Public Key:", pubKey.map(key => F.toObject(key)));

    // Sign the message
    const signature = eddsa.signPoseidon(prvKey, hash);
    // console.log("Signature:", {
    //     R8x: F.toObject(signature.R8[0]),
    //     R8y: F.toObject(signature.R8[1]),
    //     S: signature.S
    // });

    // Verify the signature
    const isValid = eddsa.verifyPoseidon(hash, signature, pubKey);
    // console.log("Signature Valid:", isValid);
    console.log({
        // Pubkey
        Ax: F.toObject(pubKey[0]).toString(),
        Ay: F.toObject(pubKey[1]).toString(),
        // Signature
        R8x: F.toObject(signature.R8[0]).toString(),
        R8y: F.toObject(signature.R8[1]).toString(),
        S: signature.S.toString(),
    })
}

main().catch(console.error);
