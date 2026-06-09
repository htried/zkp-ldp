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

export interface HostedProveResult {
  proof: Record<string, unknown>;
  publicSignals: string[];
  isValid: boolean;
  timing: {
    signMs: number;
    proveMs: number;
    verifyMs: number;
  };
  proverMode: 'local-snarkjs' | 'remote-prover';
  circuitId: string;
}

type CryptoContext = {
  poseidon: Awaited<ReturnType<typeof buildPoseidon>>;
  eddsa: Awaited<ReturnType<typeof buildEddsa>>;
  babyjubField: Awaited<ReturnType<typeof buildBabyjub>>['F'];
};

let cryptoContextPromise: Promise<CryptoContext> | null = null;

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
export async function verifyStateUpdate(input: UnsignedInput, config_path: string): Promise<boolean> {
  try {
    // Sign the input data
    const signedInput = await sign_circom_inputs(input);

    // Generate proof using the circuit
    const { proof, publicSignals } = await window.snarkjs.groth16.fullProve(
      signedInput,
      config_path + "/state.wasm",
      config_path + "/state_0001.zkey"
    );

    console.log("publicSignals", publicSignals);
    console.log("proof", proof);

    // Load verification key
    const vKey = await fetch(config_path + "/verification_key.json").then(res => res.json());
    console.log("vKey", vKey);

    // Verify the proof
    const res = await window.snarkjs.groth16.verify(vKey, publicSignals, proof);
    console.log("res", res);

    return res === true;
  } catch (error) {
    console.error("Verification failed:", error);
    return false;
  }
}

export async function proveStateUpdateViaApi(
  input: UnsignedInput,
  circuitId: string
): Promise<HostedProveResult> {
  const response = await fetch('/api/prove', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      input,
      circuitId,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Hosted prover request failed: ${response.status} ${errorText}`);
  }

  return response.json();
}
