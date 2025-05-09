import { Fingerprint } from './fingerprint_collector';
import { getFuzzyHash } from './fuzzy_hash';
import { encode } from 'ngeohash';


// Function to convert a fingerprint hash to two large integers
export function hashTo250BitStrings(hash: string): string[] {
  // Convert the hash to a binary string
  const binary = hash.split('').map(char => 
    char.charCodeAt(0).toString(2).padStart(8, '0')
  ).join('');
  
  // Split into two 250-bit strings and pad with zeros if necessary
  const first250 = binary.slice(0, 250).padEnd(250, '0');
  const second250 = binary.slice(250, 500).padEnd(250, '0');
  
  // Convert binary strings to decimal integers
  const firstInt = BigInt('0b' + first250).toString();
  const secondInt = BigInt('0b' + second250).toString();
  
  return [firstInt, secondInt];
}

// Function to flip bits in a fingerprint with probability p
export function modifyFingerprint(fingerprint: Fingerprint, p: number): Fingerprint {
  const modified: Fingerprint = {};
  let totalBits = 0;
  let flippedBits = 0;
  
  // First, convert the fingerprint to a single string
  let fingerprintString = '';
  for (const sectionKey in fingerprint) {
    const section = fingerprint[sectionKey];
    for (const key in section) {
      if (key !== '$hash' && key !== 'lied' && typeof section[key] === 'string') {
        fingerprintString += section[key];
      }
    }
  }
  
  // Flip bits in the combined string
  let modifiedString = '';
  for (let i = 0; i < fingerprintString.length; i++) {
    if (Math.random() < p) {
      modifiedString += fingerprintString[i] === '0' ? '1' : '0';
      flippedBits++;
    } else {
      modifiedString += fingerprintString[i];
    }
    totalBits++;
  }
  
  // Reconstruct the fingerprint object
  let currentIndex = 0;
  for (const sectionKey in fingerprint) {
    const section = fingerprint[sectionKey];
    const modifiedSection: { [key: string]: any; $hash?: string; lied?: boolean } = {};
    
    for (const key in section) {
      if (key === '$hash') {
        modifiedSection.$hash = section.$hash;
      } else if (key === 'lied') {
        modifiedSection.lied = section.lied;
      } else if (typeof section[key] === 'string') {
        const length = section[key].length;
        modifiedSection[key] = modifiedString.slice(currentIndex, currentIndex + length);
        currentIndex += length;
      } else {
        modifiedSection[key] = section[key];
      }
    }
    
    modified[sectionKey] = modifiedSection;
  }
  
  console.log('Total bits:', totalBits);
  console.log('Flipped bits:', flippedBits);
  console.log('Flip percentage:', (flippedBits / totalBits * 100).toFixed(2) + '%');
  
  return modified;
}

type SectionValue = {
  [key: string]: any;
  $hash?: string;
  lied?: boolean;
};

// Function to generate N modified fingerprints
export async function generateNFingerprints(fingerprint: Fingerprint, N: number, p: number): Promise<string[]> {
  const hashes: string[] = [];
  const originalFp = await getFuzzyHash(fingerprint);
  
  for (let i = 0; i < N; i++) {
    if (p === 0) {
      // For exact match, use original hash
      const [firstInt, secondInt] = hashTo250BitStrings(originalFp);
      hashes.push(`${firstInt},${secondInt}`);
    } else {
      // Convert hash to binary
      const binary = originalFp.split('').map(char => 
        char.charCodeAt(0).toString(2).padStart(8, '0')
      ).join('');
      
      // Flip bits with probability p
      let modifiedBinary = '';
      let flippedBits = 0;
      for (let i = 0; i < binary.length; i++) {
        if (Math.random() < p) {
          modifiedBinary += binary[i] === '0' ? '1' : '0';
          flippedBits++;
        } else {
          modifiedBinary += binary[i];
        }
      }
      
      // Ensure minimum number of bits are flipped for "far" option
      if (p === 0.4 && flippedBits < binary.length * 0.4) {
        const bitsToFlip = Math.floor(binary.length * 0.4) - flippedBits;
        const indices = Array.from({length: binary.length}, (_, i) => i)
          .sort(() => Math.random() - 0.5)
          .slice(0, bitsToFlip);
        
        const bits = modifiedBinary.split('');
        indices.forEach(i => {
          bits[i] = bits[i] === '0' ? '1' : '0';
        });
        modifiedBinary = bits.join('');
      }
      
      // Convert back to hex
      let modifiedHash = '';
      for (let i = 0; i < modifiedBinary.length; i += 8) {
        const byte = modifiedBinary.slice(i, i + 8);
        modifiedHash += String.fromCharCode(parseInt(byte, 2));
      }
      
      const [firstInt, secondInt] = hashTo250BitStrings(modifiedHash);
      hashes.push(`${firstInt},${secondInt}`);
    }
  }
  
  return hashes;
}

// Function to generate random coordinates within a radius
export function generateCoordinates(centerLat: number, centerLng: number, maxDistanceDegrees: number): { lat: number, lng: number } {
  // Generate random angle and distance
  const angle = Math.random() * 2 * Math.PI;
  const distance = Math.random() * maxDistanceDegrees;
  
  // Calculate new coordinates
  const lat1 = centerLat * Math.PI / 180;
  const lng1 = centerLng * Math.PI / 180;
  
  // Convert distance in degrees to radians for the calculation
  const distanceRadians = distance * Math.PI / 180;
  
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(distanceRadians) + 
                        Math.cos(lat1) * Math.sin(distanceRadians) * Math.cos(angle));
  
  const lng2 = lng1 + Math.atan2(Math.sin(angle) * Math.sin(distanceRadians) * Math.cos(lat1),
                                Math.cos(distanceRadians) - Math.sin(lat1) * Math.sin(lat2));
  
  return {
    lat: lat2 * 180 / Math.PI,
    lng: lng2 * 180 / Math.PI
  };
}

// Function to generate N geohashes
export function generateNGeohashes(centerLat: number, centerLng: number, N: number, maxDistanceMiles: number): string[] {
  return Array(N).fill(null).map(() => {
    const { lat, lng } = generateCoordinates(centerLat, centerLng, maxDistanceMiles);
    return `${lat.toFixed(6)},${lng.toFixed(6)} (${encode(lat, lng, 12)})`;
  });
}

// Function to generate random IP addresses
export async function generateRandomIPs(N: number, includeCurrent: boolean = false): Promise<string[]> {
    const ips: string[] = [];
    
    if (includeCurrent) {
      const currentIP = await fetch('https://api.ipify.org?format=json')
        .then(response => response.json())
        .then(data => data.ip);
      ips.push(currentIP);
    }
    
    // Generate remaining IPs
    while (ips.length < N) {
      const ip = Array(4).fill(0).map(() => Math.floor(Math.random() * 256)).join('.');
      if (!ips.includes(ip)) {
        ips.push(ip);
      }
    }
    
    return ips;
  }

// Function to convert IP address to integer string
export function ipToIntString(ip: string): string {
  // Convert to unsigned 32-bit integer
  return ip.split('.')
    .reduce((acc, octet) => ((acc << 8) >>> 0) + (parseInt(octet) >>> 0), 0)
    .toString();
}

export function geohashToIntString(geohash: string): string {
    // Remove any parentheses and extra text
    const cleanGeohash = geohash.split('(')[1]?.split(')')[0] || geohash;
    // Convert each character to its base32 value and combine
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    // Use simple multiplication to match test case format
    let result = 0;
    for (const char of cleanGeohash) {
      result = result * 32 + base32.indexOf(char);
    }
    return result.toString();
  } 