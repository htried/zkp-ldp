import { hashify, calculateSimilarity } from './hash_utils';
import { Fingerprint } from './fingerprint_collector';

// Define the metric keys for fuzzy hashing
const METRIC_KEYS = [
    'navigator.userAgent',
    'navigator.platform',
    'navigator.language',
    'navigator.languages',
    'navigator.hardwareConcurrency',
    'navigator.deviceMemory',
    'navigator.maxTouchPoints',
    'screen.width',
    'screen.height',
    'screen.colorDepth',
    'screen.pixelDepth',
    'screen.availWidth',
    'screen.availHeight',
    'timezone.offset',
    'timezone.zone',
    'webgl.vendor',
    'webgl.renderer',
    'webgl.version',
    'canvas.dataURI',
    'audio.data'
];

interface MetricsAll {
    [key: string]: any;
}

export const getFuzzyHash = async (fp: Fingerprint): Promise<string> => {
    // Construct map of all metrics
    const metricsAll: MetricsAll = Object.keys(fp)
        .sort()
        .reduce((acc: MetricsAll, sectionKey) => {
            const section = fp[sectionKey];
            const sectionMetrics = Object.keys(section || {})
                .sort()
                .reduce((acc: MetricsAll, key) => {
                    if (key === '$hash' || key === 'lied') {
                        return acc;
                    }
                    return { ...acc, [`${sectionKey}.${key}`]: section[key] };
                }, {});
            return { ...acc, ...sectionMetrics };
        }, {});

    // Get all values in a consistent order
    const values = METRIC_KEYS.map(key => metricsAll[key]);
    
    // Generate a single 256-bit hash
    return await hashify(values);
};

// Compare two fingerprints and return similarity score (0 to 1)
export const compareFingerprints = async (
    fp1: Fingerprint,
    fp2: Fingerprint
): Promise<number> => {
    const hash1 = await getFuzzyHash(fp1);
    const hash2 = await getFuzzyHash(fp2);
    return calculateSimilarity(hash1, hash2);
};

// Check if two fingerprints are similar based on a threshold
export const areFingerprintsSimilar = async (
    fp1: Fingerprint,
    fp2: Fingerprint,
    threshold: number = 0.8
): Promise<boolean> => {
    const similarity = await compareFingerprints(fp1, fp2);
    return similarity >= threshold;
};