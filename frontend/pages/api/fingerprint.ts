import { NextApiRequest, NextApiResponse } from 'next';
import { Fingerprint } from '../../lib/fingerprint_collector';
import { getFuzzyHash } from '../../lib/fuzzy_hash';

const fingerprintStore: { [hash: string]: Fingerprint } = {};

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  // Set CORS headers
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,POST');
  res.setHeader('Access-Control-Allow-Headers', 'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version');

  // Handle OPTIONS request for CORS preflight
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  // Only accept POST requests with JSON body
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed, please use POST' });
  }

  try {
    // Get fingerprint data from request body
    const fingerprintData = req.body as Fingerprint;
    
    if (!fingerprintData) {
      return res.status(400).json({ error: 'Fingerprint data is required' });
    }

    // Generate the fuzzy hash for the fingerprint
    const hash = await getFuzzyHash(fingerprintData);
    
    // Store the fingerprint (for demo purposes)
    fingerprintStore[hash] = fingerprintData;
    
    return res.status(200).json({
      status: 'success',
      message: 'Fingerprint collected successfully',
      hash: hash
    });
    
  } catch (error) {
    console.error('Error processing fingerprint:', error);
    const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
    return res.status(500).json({ 
      status: 'error',
      error: 'Error processing fingerprint',
      message: errorMessage
    });
  }
}