import { buildEddsa, buildBabyjub, buildPoseidon } from 'circomlibjs';

export interface UnsignedInput {
  ips: string[];
  geohashes: string[];
  last_fingerprint: string[];
  yob: string[];
  users_prf_seed: string;
  state_counter: string;
  initial_comm_rand: string;
  new_ip: string;
  new_geohash: string;
  new_rappor_nonce: string;
  new_fingerprint_nonce: string;
  state_comm_randomness: string;
  new_fingerprint: string[];
  initial_state_r8x?: string;
  initial_state_r8y?: string;
  initial_state_s?: string;
  new_user_info_r8x?: string;
  new_user_info_r8y?: string;
  new_user_info_s?: string;
}

function chainedPoseidonHash(
  poseidon: Awaited<ReturnType<typeof buildPoseidon>>,
  values: string[]
) {
  let prevHash = "0";
  const totalBlocks = Math.ceil(values.length / 15);

  for (let blockIndex = 0; blockIndex < totalBlocks; blockIndex++) {
    const start = blockIndex * 15;
    const chunk = values.slice(start, start + 15);
    const paddedChunk = [...chunk];
    while (paddedChunk.length < 15) {
      paddedChunk.push("0");
    }
    paddedChunk.push(blockIndex === 0 ? "0" : prevHash);
    const blockHash = poseidon(paddedChunk);
    prevHash = poseidon.F.toObject(blockHash).toString();
  }

  return prevHash;
}

export interface BrowserProveResult {
  proof: Record<string, unknown>;
  publicSignals: string[];
  isValid: boolean;
  proverEngine: 'rust-wasm';
  timing: {
    signMs: number;
    proveMs: number;
    verifyMs: number;
  };
  signatures: {
    initial_state: { r8x: string; r8y: string; s: string };
    new_user_info: { r8x: string; r8y: string; s: string };
  };
}

type CryptoContext = {
  poseidon: Awaited<ReturnType<typeof buildPoseidon>>;
  eddsa: Awaited<ReturnType<typeof buildEddsa>>;
  babyjubField: Awaited<ReturnType<typeof buildBabyjub>>['F'];
};

let cryptoContextPromise: Promise<CryptoContext> | null = null;
let rustWasmModulePromise: Promise<{
  default: (moduleOrPath?: RequestInfo | URL | Response | BufferSource | WebAssembly.Module) => Promise<unknown>;
  prove_groth16_json: (
    inputs_json: string,
    pkey_bytes: Uint8Array,
    graph_bytes: Uint8Array,
    r1cs_bytes: Uint8Array
  ) => string;
  verify_groth16_json: (
    proof_json: string,
    verification_key_json: string
  ) => boolean;
}> | null = null;

async function getCryptoContext(): Promise<CryptoContext> {
  if (!cryptoContextPromise) {
    cryptoContextPromise = (async () => {
      const poseidon = await buildPoseidon();
      const eddsa = await buildEddsa();
      const babyjub = await buildBabyjub();
      const babyjubField = babyjub.F;
      return { poseidon, eddsa, babyjubField };
    })();
  }
  return cryptoContextPromise;
}

async function getRustWasmModule() {
  if (!rustWasmModulePromise) {
    rustWasmModulePromise = (async () => {
      const mod = await import('../rust_wasm_prover_poc/pkg/rust_wasm_prover_poc.js');
      await mod.default();
      return mod;
    })();
  }
  return rustWasmModulePromise;
}

async function fetchBinaryAsset(path: string): Promise<Uint8Array> {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`Failed to fetch ${path}: ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

/**
 * Signs the input data for circom circuit
 * @param unsigned_input Input data to be signed
 * @returns Signed input data ready for the circuit
 */
export async function sign_circom_inputs(unsigned_input: UnsignedInput): Promise<UnsignedInput> {
  const { poseidon, eddsa, babyjubField } = await getCryptoContext();

  // Define private key (32 bytes).
  const prvKey = Buffer.from("0001020304050607080900010203040506070809000102030405060708090001", "hex");
  
  // Generate public key
  const pubKey = eddsa.prv2pub(prvKey);

  // Create state vector and hash
  const state_vec_string = [
    ...unsigned_input.ips, 
    ...unsigned_input.geohashes, 
    ...unsigned_input.last_fingerprint,
    ...unsigned_input.yob,
    unsigned_input.users_prf_seed, 
    unsigned_input.state_counter
  ];
  const state_hash = chainedPoseidonHash(poseidon, state_vec_string);

  // Create commitment vector and hash
  const comm_vec = [unsigned_input.initial_comm_rand, state_hash];
  const comm_hash = poseidon(comm_vec);
  
  // Sign the state hash
  const state_signature = eddsa.signPoseidon(prvKey, comm_hash);

  // Add signature to input
  unsigned_input.initial_state_r8x = babyjubField.toObject(state_signature.R8[0]).toString();
  unsigned_input.initial_state_r8y = babyjubField.toObject(state_signature.R8[1]).toString();
  unsigned_input.initial_state_s = state_signature.S.toString();

  // Create response vector and hash
  const response_vec_string = [
    unsigned_input.new_ip, 
    unsigned_input.new_geohash, 
    unsigned_input.new_rappor_nonce,
    unsigned_input.new_fingerprint_nonce,
  ];
  const response_hash = poseidon(response_vec_string);

  // Sign the response hash
  const response_signature = eddsa.signPoseidon(prvKey, response_hash);

  // Add response signature to input
  unsigned_input.new_user_info_r8x = babyjubField.toObject(response_signature.R8[0]).toString();
  unsigned_input.new_user_info_r8y = babyjubField.toObject(response_signature.R8[1]).toString();
  unsigned_input.new_user_info_s = response_signature.S.toString();

  return unsigned_input;
}

/**
 * Verifies a state update using the circom circuit
 * @param input The input data to verify
 * @returns Promise that resolves to true if verification succeeds
 */
export async function proveStateUpdateInBrowserRustWasm(
  input: UnsignedInput,
  configPath: string,
  rustAssetsPath = `${configPath}/rust`
): Promise<BrowserProveResult> {
  const signStart = performance.now();
  const signedInput = await sign_circom_inputs(input);
  const signEnd = performance.now();

  const proveStart = performance.now();
  const [rustModule, pkeyBytes, graphBytes, r1csBytes] = await Promise.all([
    getRustWasmModule(),
    fetchBinaryAsset(`${rustAssetsPath}/state.ark-pkey`),
    fetchBinaryAsset(`${rustAssetsPath}/state.graph`),
    fetchBinaryAsset(`${rustAssetsPath}/state.r1cs`),
  ]);

  let proofJson: string;
  try {
    proofJson = rustModule.prove_groth16_json(
      JSON.stringify(signedInput),
      pkeyBytes,
      graphBytes,
      r1csBytes
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('Invalid magic')) {
      throw new Error(
        'Rust prover graph format mismatch: arkworks expects build-circuit graph bytes, but this circuit currently ships CVM witnesscalc bytecode.'
      );
    }
    throw err;
  }
  const parsedProof = JSON.parse(proofJson) as Record<string, unknown>;
  const proof = (parsedProof.proof as Record<string, unknown> | undefined) ?? parsedProof;
  const publicSignals = Array.isArray(parsedProof.inputs)
    ? parsedProof.inputs.map((value) => String(value))
    : [];
  const proveEnd = performance.now();

  const verifyStart = performance.now();
  const arkVKeyJson = await fetch(`${rustAssetsPath}/state.ark-vk.json`).then((res) => {
    if (!res.ok) {
      throw new Error(`Failed to fetch ${rustAssetsPath}/state.ark-vk.json: ${res.status}`);
    }
    return res.text();
  });
  const isValid = rustModule.verify_groth16_json(proofJson, arkVKeyJson);
  const verifyEnd = performance.now();

  return {
    proof,
    publicSignals,
    isValid,
    proverEngine: 'rust-wasm',
    timing: {
      signMs: signEnd - signStart,
      proveMs: proveEnd - proveStart,
      verifyMs: verifyEnd - verifyStart,
    },
    signatures: {
      initial_state: {
        r8x: signedInput.initial_state_r8x || '',
        r8y: signedInput.initial_state_r8y || '',
        s: signedInput.initial_state_s || '',
      },
      new_user_info: {
        r8x: signedInput.new_user_info_r8x || '',
        r8y: signedInput.new_user_info_r8y || '',
        s: signedInput.new_user_info_s || '',
      },
    },
  };
}

