import { Canvas } from 'canvas';

// SimHash implementation for similarity comparison
function hashString(str: string): number {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);

        // djb2 hash algorithm -- multiply by 32, subtract original hash, then add the character code
        hash = ((hash << 5) - hash) + char;
        // Convert to 32bit integer by bitwise ANDing with itself
        hash = hash & hash;
    }
    return hash;
}

// Convert a value to a string representation
function valueToString(value: any): string {
    if (value === null || value === undefined) {
        return '';
    }
    if (typeof value === 'object') {
        return JSON.stringify(value);
    }
    return String(value);
}

// Generate feature hashes for SimHash
function generateFeatureHashes(value: string): number[] {
    const hashes: number[] = new Array(512).fill(0);
    const words = value.toLowerCase().split(/\s+/);
    
    // Weight different components differently
    const weights: { [key: string]: number } = {
        // High distinctiveness (weight 8)
        'useragent': 8,
        'webgl': 8,
        'canvas': 8,
        'audio': 8,
        
        // Medium-high distinctiveness (weight 6)
        'platform': 6,
        'hardware': 6,
        'screen': 6,
        
        // Medium distinctiveness (weight 4)
        'language': 4,
        'timezone': 4,
        
        // Low distinctiveness (weight 2)
        'max': 2,
        'avail': 2,
        'depth': 2,
        'width': 2,
        'height': 2
    };
    
    // Process each word with its context
    for (let i = 0; i < words.length; i++) {
        const word = words[i];
        const nextWord = words[i + 1] || '';
        const prevWord = words[i - 1] || '';
        
        // Find the highest matching weight for this word and its context
        let weight = 1; // Default weight
        for (const [key, value] of Object.entries(weights)) {
            if (word.includes(key) || 
                (nextWord && nextWord.includes(key)) || 
                (prevWord && prevWord.includes(key))) {
                weight = Math.max(weight, value);
            }
        }
        
        // Generate hash with higher weight for more distinctive features
        const hash = hashString(word);
        for (let i = 0; i < 512; i++) {
            const bit = (hash >> (i % 32)) & 1;
            // Square the weight to increase differentiation
            hashes[i] += bit ? weight * weight : -weight * weight;
        }
    }
    
    // Normalize the hashes to prevent overflow
    const maxValue = Math.max(...hashes.map(Math.abs));
    if (maxValue > 0) {
        for (let i = 0; i < hashes.length; i++) {
            hashes[i] = Math.sign(hashes[i]) * Math.min(Math.abs(hashes[i]), 1);
        }
    }
    
    return hashes;
}

// Convert feature hashes to SimHash
function hashesToSimHash(hashes: number[]): string {
    return hashes
        .map(h => h > 0 ? '1' : '0')
        .join('');
}

// Hash an array of values using SimHash
export async function hashify(values: any[]): Promise<string> {
    // Convert all values to strings and concatenate
    const combinedString = values.map(valueToString).join(' ');
    
    // Generate feature hashes
    const featureHashes = generateFeatureHashes(combinedString);
    
    // Convert to SimHash
    return hashesToSimHash(featureHashes);
}

// Calculate Hamming distance between two hashes
export function hammingDistance(hash1: string, hash2: string): number {
    let distance = 0;
    for (let i = 0; i < hash1.length; i++) {
        if (hash1[i] !== hash2[i]) {
            distance++;
        }
    }
    return distance;
}

// Calculate similarity between two hashes (0 to 1)
export function calculateSimilarity(hash1: string, hash2: string): number {
    const distance = hammingDistance(hash1, hash2);
    return 1 - (distance / hash1.length);
} 

// Generate a random canvas fingerprint (used for testing)
export function generateRandomCanvasFingerprint(): string {
    // Create a canvas element - handle both browser and Node.js environments
    const canvas = typeof document !== 'undefined' 
        ? document.createElement('canvas') 
        : new Canvas(200, 200);
    const ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
    
    if (!ctx) {
        throw new Error('Could not get canvas context');
    }

    // Set canvas size
    canvas.width = 200;
    canvas.height = 200;

    // Fill background with random color
    ctx.fillStyle = `rgb(${Math.random() * 255}, ${Math.random() * 255}, ${Math.random() * 255})`;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Draw random shapes
    for (let i = 0; i < 10; i++) {
        ctx.beginPath();
        ctx.fillStyle = `rgb(${Math.random() * 255}, ${Math.random() * 255}, ${Math.random() * 255})`;
        
        // Randomly choose between rectangle, circle, or triangle
        const shape = Math.floor(Math.random() * 3);
        const x = Math.random() * canvas.width;
        const y = Math.random() * canvas.height;
        const size = 20 + Math.random() * 30;

        switch (shape) {
            case 0: // Rectangle
                ctx.fillRect(x, y, size, size);
                break;
            case 1: // Circle
                ctx.arc(x, y, size/2, 0, Math.PI * 2);
                ctx.fill();
                break;
            case 2: // Triangle
                ctx.moveTo(x, y);
                ctx.lineTo(x + size, y);
                ctx.lineTo(x + size/2, y + size);
                ctx.fill();
                break;
        }
    }

    // Add some random text
    ctx.fillStyle = 'white';
    ctx.font = '20px Arial';
    ctx.fillText('Test', Math.random() * canvas.width, Math.random() * canvas.height);

    // Convert to base64
    return canvas.toDataURL();
}