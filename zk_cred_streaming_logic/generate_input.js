const fs = require('fs');
const { buildEddsa, buildBabyjub, buildPoseidon } = require("circomlibjs");

// Configuration
const config = {
    // Test coordinates (San Francisco area)
    baseLat: 37.7749,
    baseLng: -122.4194,

    // Number of geohashes to simulate in the state
    stateCounter: 3,

    // Coordinate precision (1e6 for 6 decimal places)
    precision: 1000000,

    // Test values
    usersPrfSeed: "1234567890",
    yob: ["48", "48"], // 2000 birth year
    fingerprint: [
        "000000000000000000000000000000000000000000000000000000000000000000000000000",
        "11111111111111111111111111111111111111111111111111111111111111111111111111"
    ]
};


// Helper function to convert coordinates to geohash
function coordinatesToGeohash(lat, lng) {
    // Scale coordinates to integers
    const latInt = Math.floor((lat + 180) * config.precision);
    const lngInt = Math.floor((lng + 360) * config.precision);

    // Convert to 32-bit binary strings
    const latBits = latInt.toString(2).padStart(32, '0');
    const lngBits = lngInt.toString(2).padStart(32, '0');

    // Interleave bits (longitude first, then latitude)
    let geohashBits = '';
    for (let i = 0; i < 32; i++) {
        geohashBits += lngBits[i] + latBits[i];
    }

    // Convert back to decimal
    return BigInt('0b' + geohashBits);
}

// Helper function to generate random coordinates within a radius
function generateRandomCoordinates(baseLat, baseLng, radiusKm) {
    // Convert radius to degrees (approximate)
    const latRadius = radiusKm / 111.32; // 1 degree latitude ≈ 111.32 km
    const lngRadius = radiusKm / (111.32 * Math.cos(baseLat * Math.PI / 180));

    // Generate random offset
    const latOffset = (Math.random() - 0.5) * 2 * latRadius;
    const lngOffset = (Math.random() - 0.5) * 2 * lngRadius;

    return {
        lat: baseLat + latOffset,
        lng: baseLng + lngOffset
    };
}

// Generate test data
function generateTestData() {
    const coordinates = [];
    let latSum = 0;
    let lngSum = 0;
    let geohashSum = BigInt(0);

    // Generate base coordinates and variations
    for (let i = 0; i < config.stateCounter; i++) {
        let coord;
        if (i === 0) {
            // First coordinate is the base
            coord = { lat: config.baseLat, lng: config.baseLng };
        } else {
            // Generate nearby coordinates (within ~1km)
            coord = generateRandomCoordinates(config.baseLat, config.baseLng, 1.0);
        }

        coordinates.push(coord);

        // Convert to integer coordinates
        const latInt = Math.floor((coord.lat + 180) * config.precision);
        const lngInt = Math.floor((coord.lng + 360) * config.precision);

        latSum += latInt;
        lngSum += lngInt;

        // Convert to geohash and add to sum
        const geohash = coordinatesToGeohash(coord.lat, coord.lng);
        geohashSum += geohash;
    }

    // Calculate average geohash
    const avgGeohash = geohashSum / BigInt(config.stateCounter);

    // Generate a new geohash that's close to the average
    const newCoord = generateRandomCoordinates(config.baseLat, config.baseLng, 0.5);
    const newGeohash = coordinatesToGeohash(newCoord.lat, newCoord.lng);

    return {
        coordinates,
        latSum,
        lngSum,
        geohashSum: geohashSum.toString(),
        avgGeohash: avgGeohash.toString(),
        newGeohash: newGeohash.toString(),
        latSum,
        lngSum
    };
}

// Generate real signatures using circomlibjs
async function signCircomInputs(unsignedInput) {
    const poseidon = await buildPoseidon();
    const F_Poseidon = poseidon.F;
    const eddsa = await buildEddsa();
    const babyJub = await buildBabyjub();
    const F = babyJub.F;

    // Use the same private key as the original script
    const prvKey = Buffer.from("0001020304050607080900010203040506070809000102030405060708090001", "hex");
    const pubKey = eddsa.prv2pub(prvKey);

    // Create state hash with new structure (10 fields) - EXACTLY as the circuit expects
    // [geohash_sum, state_counter, avg_geohash, lat_sum, lng_sum, last_fingerprint[0], last_fingerprint[1], yob[0], yob[1], users_prf_seed]
    const stateVecString = [
        unsignedInput.geohash_sum,
        unsignedInput.state_counter,
        unsignedInput.avg_geohash,
        unsignedInput.lat_sum,
        unsignedInput.lng_sum,
        unsignedInput.last_fingerprint[0],
        unsignedInput.last_fingerprint[1],
        unsignedInput.yob[0],
        unsignedInput.yob[1],
        unsignedInput.users_prf_seed
    ];

    // console.log('\n=== DEBUG: State Hash Calculation ===');
    // console.log('State vector for hashing:');
    // stateVecString.forEach((val, i) => {
    //     console.log(`  [${i}]: ${val}`);
    // });

    // Use single Poseidon(10) hash instead of chained hash to match circuit
    let stateHash = poseidon(stateVecString.map(x => poseidon.F.e(x)));
    // console.log(`State hash: ${F_Poseidon.toObject(stateHash).toString()}`);

    const commVec = [unsignedInput.initial_comm_rand, F_Poseidon.toObject(stateHash).toString()];
    // console.log('Commitment vector:', commVec);

    let commHash = poseidon(commVec.map(x => poseidon.F.e(x)));
    // console.log(`Commitment hash: ${F_Poseidon.toObject(commHash).toString()}`);

    const stateSignature = eddsa.signPoseidon(prvKey, commHash);

    unsignedInput.initial_state_r8x = F.toObject(stateSignature.R8[0]).toString();
    unsignedInput.initial_state_r8y = F.toObject(stateSignature.R8[1]).toString();
    unsignedInput.initial_state_s = stateSignature.S.toString();

    // console.log('Generated state signature:');
    // console.log(`  R8x: ${unsignedInput.initial_state_r8x}`);
    // console.log(`  R8y: ${unsignedInput.initial_state_r8y}`);
    // console.log(`  S: ${unsignedInput.initial_state_s}`);

    // Create response hash for server response signature
    const responseVecString = [unsignedInput.new_geohash, unsignedInput.new_rappor_nonce, unsignedInput.new_fingerprint_nonce];
    // console.log('\n=== DEBUG: Response Hash Calculation ===');
    // console.log('Response vector for hashing:', responseVecString);

    let responseHash = poseidon(responseVecString.map(x => poseidon.F.e(x)));
    // console.log(`Response hash: ${F_Poseidon.toObject(responseHash).toString()}`);

    const responseSignature = eddsa.signPoseidon(prvKey, responseHash);

    unsignedInput.new_user_info_r8x = F.toObject(responseSignature.R8[0]).toString();
    unsignedInput.new_user_info_r8y = F.toObject(responseSignature.R8[1]).toString();
    unsignedInput.new_user_info_s = responseSignature.S.toString();

    // console.log('Generated response signature:');
    // console.log(`  R8x: ${unsignedInput.new_user_info_r8x}`);
    // console.log(`  R8y: ${unsignedInput.new_user_info_r8y}`);
    // console.log(`  S: ${unsignedInput.new_user_info_s}`);

    return unsignedInput;
}

// Clean inputs (convert BigInts to strings)
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

// Main function to generate input
async function generateInput() {
    console.log('Generating test input for state_streaming circuit...');

    const testData = generateTestData();

    // Create unsigned input
    const unsignedInput = {
        geohash_sum: testData.geohashSum,
        state_counter: config.stateCounter.toString(),
        avg_geohash: testData.avgGeohash,
        lat_sum: testData.latSum.toString(),
        lng_sum: testData.lngSum.toString(),
        last_fingerprint: config.fingerprint,
        yob: config.yob,
        users_prf_seed: config.usersPrfSeed,
        initial_comm_rand: Math.floor(Math.random() * 1000000000000000).toString(),
        new_geohash: testData.newGeohash,
        new_rappor_nonce: Math.floor(Math.random() * 1000000).toString(),
        new_fingerprint_nonce: Math.floor(Math.random() * 1000000000).toString(),
        state_comm_randomness: Math.floor(Math.random() * 1000000000000000).toString(),
        new_fingerprint: config.fingerprint
    };

    // Sign the input
    const signedInput = await signCircomInputs(unsignedInput);
    const cleanInput = cleanInputs(signedInput);

    // Write to file
    const filename = 'input.json';
    fs.writeFileSync(filename, JSON.stringify(cleanInput, null, 2));

    console.log(`Input file generated: ${filename}`);
    // console.log('\nGenerated coordinates:');
    // testData.coordinates.forEach((coord, i) => {
    //     console.log(`  ${i + 1}. Lat: ${coord.lat.toFixed(6)}, Lng: ${coord.lng.toFixed(6)}`);
    // });
    // console.log(`\nNew geohash coordinates: Lat: ${testData.coordinates[0].lat.toFixed(6)}, Lng: ${testData.coordinates[0].lng.toFixed(6)}`);
    // console.log(`\nCoordinate sums: lat_sum=${testData.latSum}, lng_sum=${testData.lngSum}`);
    // console.log(`\nGeohash sums: geohash_sum=${testData.geohashSum}, avg_geohash=${testData.avgGeohash}`);

    return cleanInput;
}

// Run the generator
if (require.main === module) {
    (async () => {
        try {
            // Generate single input
            await generateInput();

        } catch (error) {
            console.error(error);
            process.exit(1);
        }
    })();
}

module.exports = {
    generateInput,
    coordinatesToGeohash,
    generateRandomCoordinates
};
