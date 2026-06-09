const path = require('path');
const fs = require('fs/promises');
const { performance } = require('perf_hooks');
const { execFile } = require('child_process');
const { promisify } = require('util');
const snarkjs = require('snarkjs');
const { buildEddsa, buildBabyjub, buildPoseidon } = require('circomlibjs');
const execFileAsync = promisify(execFile);

const SUPPORTED_CIRCUIT_IDS = new Set(['gh_20_fp_400']);

const DEFAULT_CIRCUIT_ID = 'gh_20_fp_400';
let cryptoContextPromise = null;

async function getCryptoContext() {
  if (!cryptoContextPromise) {
    cryptoContextPromise = (async () => {
      const poseidon = await buildPoseidon();
      const eddsa = await buildEddsa();
      const babyJub = await buildBabyjub();
      return { poseidon, eddsa, babyJubField: babyJub.F };
    })();
  }
  return cryptoContextPromise;
}

function resolveProverBinaryPath() {
  if (process.env.RAPIDSNARK_BINARY_PATH) {
    return process.env.RAPIDSNARK_BINARY_PATH;
  }

  // Lambda arm64 runtimes expose process.arch === "arm64".
  if (process.arch === 'arm64') {
    return '/var/task/prove_verify/prover_linux_arm64';
  }

  return '/var/task/prove_verify/prover_linux_x64';
}

function response(statusCode, body) {
  return {
    statusCode,
    headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'POST,OPTIONS',
      'access-control-allow-headers': 'content-type',
    },
    body: JSON.stringify(body),
  };
}

function parseBody(event) {
  if (!event || typeof event.body !== 'string') return null;
  try {
    return JSON.parse(event.body);
  } catch {
    return null;
  }
}

async function signCircomInputs(unsignedInput) {
  const { poseidon, eddsa, babyJubField } = await getCryptoContext();
  const chainedPoseidonHash = (values) => {
    let previousHash = '0';
    const totalBlocks = Math.ceil(values.length / 15);

    for (let blockIndex = 0; blockIndex < totalBlocks; blockIndex++) {
      const start = blockIndex * 15;
      const chunk = values.slice(start, start + 15);
      const paddedChunk = [...chunk];
      while (paddedChunk.length < 15) {
        paddedChunk.push('0');
      }
      paddedChunk.push(blockIndex === 0 ? '0' : previousHash);
      const blockHash = poseidon(paddedChunk);
      previousHash = poseidon.F.toObject(blockHash).toString();
    }

    return previousHash;
  };
  const privateKey = Buffer.from(
    '0001020304050607080900010203040506070809000102030405060708090001',
    'hex'
  );

  const stateVector = [
    ...unsignedInput.ips,
    ...unsignedInput.geohashes,
    ...unsignedInput.last_fingerprint,
    ...unsignedInput.yob,
    unsignedInput.users_prf_seed,
    unsignedInput.state_counter,
  ];
  const stateHash = chainedPoseidonHash(stateVector);

  const commitmentVector = [
    unsignedInput.initial_comm_rand,
    stateHash,
  ];
  const commitmentHash = poseidon(commitmentVector);
  const stateSignature = eddsa.signPoseidon(privateKey, commitmentHash);

  unsignedInput.initial_state_r8x = babyJubField.toObject(stateSignature.R8[0]).toString();
  unsignedInput.initial_state_r8y = babyJubField.toObject(stateSignature.R8[1]).toString();
  unsignedInput.initial_state_s = stateSignature.S.toString();

  const responseVector = [
    unsignedInput.new_ip,
    unsignedInput.new_geohash,
    unsignedInput.new_rappor_nonce,
    unsignedInput.new_fingerprint_nonce,
  ];
  const responseHash = poseidon(responseVector);
  const responseSignature = eddsa.signPoseidon(privateKey, responseHash);

  unsignedInput.new_user_info_r8x = babyJubField.toObject(responseSignature.R8[0]).toString();
  unsignedInput.new_user_info_r8y = babyJubField.toObject(responseSignature.R8[1]).toString();
  unsignedInput.new_user_info_s = responseSignature.S.toString();

  return unsignedInput;
}

function hasInputSignatures(input) {
  return Boolean(
    input.initial_state_r8x &&
      input.initial_state_r8y &&
      input.initial_state_s &&
      input.new_user_info_r8x &&
      input.new_user_info_r8y &&
      input.new_user_info_s
  );
}

exports.handler = async (event) => {
  if (event && event.requestContext && event.requestContext.http && event.requestContext.http.method === 'OPTIONS') {
    return response(200, { ok: true });
  }

  const parsed = parseBody(event);
  if (!parsed || !parsed.input) {
    return response(400, { error: 'Request body must include { input, circuitId? }' });
  }

  const input = parsed.input;
  if (
    !Array.isArray(input.ips) ||
    !Array.isArray(input.geohashes) ||
    !Array.isArray(input.last_fingerprint) ||
    !Array.isArray(input.yob)
  ) {
    return response(400, { error: 'input.ips, input.geohashes, input.last_fingerprint, input.yob are required arrays' });
  }

  const circuitId =
    typeof parsed.circuitId === 'string' && SUPPORTED_CIRCUIT_IDS.has(parsed.circuitId)
      ? parsed.circuitId
      : DEFAULT_CIRCUIT_ID;

  try {
    const signStart = performance.now();
    const signedInput = hasInputSignatures(input) ? input : await signCircomInputs(input);
    const signEnd = performance.now();

    const circuitDir = path.join('/var/task/frontend/public', circuitId);
    const wasmPath = path.join(circuitDir, 'state.wasm');
    const zkeyPath = path.join(circuitDir, 'state_0001.zkey');

    const proveStart = performance.now();
    const proofRunId = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const witnessPath = `/tmp/${proofRunId}-witness.wtns`;
    const proofPath = `/tmp/${proofRunId}-proof.json`;
    const publicPath = `/tmp/${proofRunId}-public.json`;
    const proverBinaryPath = resolveProverBinaryPath();

    await snarkjs.wtns.calculate(signedInput, wasmPath, witnessPath);
    await execFileAsync(proverBinaryPath, [zkeyPath, witnessPath, proofPath, publicPath], {
      timeout: 55000,
      maxBuffer: 10 * 1024 * 1024,
    });

    const proof = JSON.parse(await fs.readFile(proofPath, 'utf8'));
    const publicSignals = JSON.parse(await fs.readFile(publicPath, 'utf8'));
    const proveEnd = performance.now();

    // Best-effort temp cleanup.
    await Promise.allSettled([
      fs.unlink(witnessPath),
      fs.unlink(proofPath),
      fs.unlink(publicPath),
    ]);

    return response(200, {
      proof,
      publicSignals,
      circuitId,
      timing: {
        signMs: signEnd - signStart,
        proveMs: proveEnd - proveStart,
        verifyMs: 0,
      },
    });
  } catch (error) {
    console.error('prover_error', error);
    return response(500, {
      error: 'Error processing proof request',
      details: error instanceof Error ? error.message : String(error),
    });
  }
};
