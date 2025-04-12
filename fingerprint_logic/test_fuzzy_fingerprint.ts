import { getFuzzyHash, compareFingerprints, areFingerprintsSimilar } from './fuzzy_fingerprint.js';
import { Fingerprint } from './fingerprint_collector.js';
import { generateRandomCanvasFingerprint } from './hash_utils.js';

// Base32 alphabet (RFC 4648)
const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

// Convert binary string to base32
function convertToBase32(binary: string): string {
    // Pad the binary string to be divisible by 5
    const padding = (5 - (binary.length % 5)) % 5;
    const paddedBinary = binary + '0'.repeat(padding);
    
    let result = '';
    // Process 5 bits at a time
    for (let i = 0; i < paddedBinary.length; i += 5) {
        const chunk = paddedBinary.slice(i, i + 5);
        const value = parseInt(chunk, 2);
        result += BASE32_ALPHABET[value];
    }
    
    // Add padding characters if needed
    if (padding > 0) {
        result += '='.repeat(Math.ceil(padding / 5));
    }
    
    return result;
}

// Sample fingerprints from my device
const fp1: Fingerprint = {
    navigator: {
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
        platform: "MacIntel",
        language: "en-US",
        languages: [
            "en-US",
            "en"
        ],
        hardwareConcurrency: 8,
        deviceMemory: 8,
        maxTouchPoints: 0
    },
    screen: {
        width: 1792,
        height: 1120,
        colorDepth: 24,
        pixelDepth: 24,
        availWidth: 1792,
        availHeight: 1095
    },
    timezone: {
        offset: 240,
        zone: "America/New_York"
    },
    webgl: {
        vendor: "Google Inc. (Intel)",
        renderer: "ANGLE (Intel, ANGLE Metal Renderer: Intel(R) UHD Graphics 630, Unspecified Version)",
        version: "WebGL 1.0 (OpenGL ES 2.0 Chromium)"
    },
    canvas: {
        dataURI: generateRandomCanvasFingerprint()
    },
    audio: {
        data: []
    }
};

const fp2: Fingerprint = {
    navigator: {
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
        platform: "Win32",
        language: "en-GB",
        languages: [
            "en-GB",
            "en"
        ],
        hardwareConcurrency: 4,
        deviceMemory: 4,
        maxTouchPoints: 2
    },
    screen: {
        width: 1920,
        height: 1080,
        colorDepth: 24,
        pixelDepth: 24,
        availWidth: 1920,
        availHeight: 1040
    },
    timezone: {
        offset: 60,
        zone: "Europe/London"
    },
    webgl: {
        vendor: "Google Inc.",
        renderer: "ANGLE (NVIDIA, NVIDIA GeForce GTX 1060 Direct3D11 vs_5_0 ps_5_0)",
        version: "WebGL 1.0 (OpenGL ES 2.0 Chromium)"
    },
    canvas: {
        dataURI: generateRandomCanvasFingerprint()
    },
    audio: {
        data: []
    }
};

async function testFuzzyFingerprint(fp1: Fingerprint, fp2: Fingerprint) {
    try {
        // Get fuzzy hashes
        const hash1 = await getFuzzyHash(fp1);
        const hash2 = await getFuzzyHash(fp2);
        
        // Convert hashes to base32 strings
        const base32Hash1 = convertToBase32(hash1);
        const base32Hash2 = convertToBase32(hash2);

        console.log('Fingerprint 1 Hash:', base32Hash1);
        console.log('Fingerprint 2 Hash:', base32Hash2);

        // Compare fingerprints
        const similarity = await compareFingerprints(fp1, fp2);
        console.log('Similarity Score:', similarity);

        // Check if fingerprints are similar
        const areSimilar = await areFingerprintsSimilar(fp1, fp2);
        console.log('Are Fingerprints Similar?', areSimilar);

        // Test with different thresholds
        const thresholds = [0.7, 0.8, 0.9];
        for (const threshold of thresholds) {
            const similar = await areFingerprintsSimilar(fp1, fp2, threshold);
            console.log(`Similar with threshold ${threshold}?`, similar);
        }

    } catch (error) {
        console.error('Error testing fuzzy fingerprint:', error);
    }
}

(async () => {
    console.log("=============================================");
    console.log("Similarity between two identical fingerprints");
    console.log("=============================================\n")
    await testFuzzyFingerprint(fp1, fp1);
    
    console.log("\n========================================================");
    console.log("Similarity between two completely different fingerprints");
    console.log("========================================================\n");
    await testFuzzyFingerprint(fp1, fp2);
})();