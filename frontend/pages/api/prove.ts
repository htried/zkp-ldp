import { NextApiRequest, NextApiResponse } from 'next';
import * as snarkjs from 'snarkjs';
import path from 'path';
import { sign_circom_inputs, UnsignedInput } from '../../lib/zk_utils';

type ProofResponse = {
  proof: any;
  publicSignals: string[];
  isValid: boolean;
};

type ErrorResponse = {
  error: string;
  details?: string;
};

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<ProofResponse | ErrorResponse>
) {
  // Set CORS headers
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,POST');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

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
    // Get input data from request body
    const inputData = req.body as UnsignedInput;
    
    if (!inputData) {
      return res.status(400).json({ error: 'Request body is required' });
    }

    // Sign the inputs
    const signedInput = await sign_circom_inputs(inputData);
    
    // Path to the wasm and zkey files
    // In Vercel, these need to be in the 'public' directory and referenced accordingly
    const wasmPath = path.join(process.cwd(), 'public', 'state.wasm');
    const zkeyPath = path.join(process.cwd(), 'public', 'state_0001.zkey');
    const vKeyPath = path.join(process.cwd(), 'public', 'verification_key.json');
    
    // Generate proof
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
      signedInput, 
      wasmPath, 
      zkeyPath
    );
    
    // Verify the proof
    // Using dynamic import for JSON file to work with TypeScript
    const vKey = require(vKeyPath);
    const isValid = await snarkjs.groth16.verify(vKey, publicSignals, proof);
    
    // Return the results
    return res.status(200).json({
      proof,
      publicSignals,
      isValid,
    });
    
  } catch (error) {
    console.error('Error generating or verifying proof:', error);
    return res.status(500).json({ 
      error: 'Error processing request', 
      details: error instanceof Error ? error.message : String(error)
    });
  }
}