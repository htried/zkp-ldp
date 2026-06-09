import { UnsignedInput } from './zk_utils';

export const SUPPORTED_CIRCUIT_IDS = [
  'gh_20_fp_400',
] as const;

export type CircuitId = (typeof SUPPORTED_CIRCUIT_IDS)[number];

export const DEFAULT_CIRCUIT_ID: CircuitId = 'gh_20_fp_400';

export type ProverMode = 'local-snarkjs' | 'remote-prover';

export type ProofLike = Record<string, unknown>;

export interface ProveRequestBody {
  input: UnsignedInput;
  circuitId?: string;
}

export interface ProveTiming {
  signMs: number;
  proveMs: number;
  verifyMs: number;
}

export interface ProveResponse {
  proof: ProofLike;
  publicSignals: string[];
  isValid: boolean;
  timing: ProveTiming;
  proverMode: ProverMode;
  circuitId: CircuitId;
}

export function resolveCircuitId(maybeCircuitId?: string): CircuitId {
  if (!maybeCircuitId) return DEFAULT_CIRCUIT_ID;
  return SUPPORTED_CIRCUIT_IDS.includes(maybeCircuitId as CircuitId)
    ? (maybeCircuitId as CircuitId)
    : DEFAULT_CIRCUIT_ID;
}
