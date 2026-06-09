import { NextApiRequest, NextApiResponse } from 'next';
import * as snarkjs from 'snarkjs';
import path from 'path';
import { readFile } from 'fs/promises';
import { sign_circom_inputs, UnsignedInput } from '../../lib/zk_utils';
import {
  ProveRequestBody,
  ProveResponse,
  ProverMode,
  resolveCircuitId,
} from '../../lib/prover_types';

type RemoteProverResponse = {
  proof: any;
  publicSignals: string[];
};

type ErrorResponse = {
  error: string;
  details?: string;
};

const verificationKeyCache = new Map<string, unknown>();

function hasInputSignatures(input: UnsignedInput): boolean {
  return Boolean(
    input.initial_state_r8x &&
      input.initial_state_r8y &&
      input.initial_state_s &&
      input.new_user_info_r8x &&
      input.new_user_info_r8y &&
      input.new_user_info_s
  );
}

function getProverMode(): ProverMode {
  return process.env.PROVER_MODE === 'remote-prover' ? 'remote-prover' : 'local-snarkjs';
}

async function proveLocally(
  signedInput: UnsignedInput,
  wasmPath: string,
  zkeyPath: string
): Promise<RemoteProverResponse> {
  const { proof, publicSignals } = await snarkjs.groth16.fullProve(signedInput, wasmPath, zkeyPath);
  return { proof, publicSignals };
}

async function proveRemotely(
  signedInput: UnsignedInput,
  circuitId: string
): Promise<RemoteProverResponse> {
  const externalProverUrl = process.env.EXTERNAL_PROVER_URL;
  if (!externalProverUrl) {
    throw new Error('EXTERNAL_PROVER_URL is required when PROVER_MODE=remote-prover');
  }

  const resp = await fetch(externalProverUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ input: signedInput, circuitId }),
  });

  if (!resp.ok) {
    const responseText = await resp.text();
    throw new Error(`Remote prover failed: ${resp.status} ${responseText}`);
  }

  const data = (await resp.json()) as Partial<RemoteProverResponse>;
  if (!data.proof || !Array.isArray(data.publicSignals)) {
    throw new Error('Remote prover response is missing proof/publicSignals');
  }

  return {
    proof: data.proof,
    publicSignals: data.publicSignals,
  };
}

async function getVerificationKey(vKeyPath: string): Promise<any> {
  const cached = verificationKeyCache.get(vKeyPath);
  if (cached) return cached;
  const vKeyRaw = await readFile(vKeyPath, 'utf8');
  const vKey = JSON.parse(vKeyRaw);
  verificationKeyCache.set(vKeyPath, vKey);
  return vKey;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<ProveResponse | ErrorResponse>
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
    const requestBody = req.body as Partial<ProveRequestBody> | UnsignedInput;
    const inputData = (requestBody as ProveRequestBody).input
      ? (requestBody as ProveRequestBody).input
      : (requestBody as UnsignedInput);

    if (!inputData) {
      return res.status(400).json({ error: 'Request body is required' });
    }
    if (
      !Array.isArray(inputData.ips) ||
      !Array.isArray(inputData.geohashes) ||
      !Array.isArray(inputData.last_fingerprint) ||
      !Array.isArray(inputData.yob)
    ) {
      return res.status(400).json({
        error: 'input.ips, input.geohashes, input.last_fingerprint, and input.yob are required arrays',
      });
    }

    const circuitId = resolveCircuitId((requestBody as ProveRequestBody).circuitId);
    const proverMode = getProverMode();

    const signStart = performance.now();
    const signedInput = hasInputSignatures(inputData)
      ? inputData
      : await sign_circom_inputs(inputData);
    const signEnd = performance.now();

    const circuitPath = path.join(process.cwd(), 'public', circuitId);
    const wasmPath = path.join(circuitPath, 'state.wasm');
    const zkeyPath = path.join(circuitPath, 'state_0001.zkey');
    const vKeyPath = path.join(circuitPath, 'verification_key.json');

    const proveStart = performance.now();
    const { proof, publicSignals } =
      proverMode === 'remote-prover'
        ? await proveRemotely(signedInput, circuitId)
        : await proveLocally(signedInput, wasmPath, zkeyPath);
    const proveEnd = performance.now();

    const verifyStart = performance.now();
    const vKey = await getVerificationKey(vKeyPath);
    const isValid = await snarkjs.groth16.verify(vKey, publicSignals, proof);
    const verifyEnd = performance.now();

    return res.status(200).json({
      proof,
      publicSignals,
      isValid,
      timing: {
        signMs: signEnd - signStart,
        proveMs: proveEnd - proveStart,
        verifyMs: verifyEnd - verifyStart,
      },
      proverMode,
      circuitId,
    });
  } catch (error) {
    console.error('Error generating or verifying proof:', error);
    return res.status(500).json({
      error: 'Error processing request',
      details: error instanceof Error ? error.message : String(error)
    });
  }
}