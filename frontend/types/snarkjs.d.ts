declare module 'snarkjs' {
  export interface Groth16Proof {
    pi_a: [string, string, string];
    pi_b: [[string, string], [string, string], [string, string]];
    pi_c: [string, string, string];
    protocol: string;
    curve: string;
  }

  export interface Groth16VerificationKey {
    protocol: string;
    curve: string;
    nPublic: number;
    vk_alpha_1: [string, string, string];
    vk_beta_2: [[string, string], [string, string], [string, string]];
    vk_gamma_2: [[string, string], [string, string], [string, string]];
    vk_delta_2: [[string, string], [string, string], [string, string]];
    vk_alphabeta_12: [[[string, string], [string, string], [string, string]], [[string, string], [string, string], [string, string]]];
    IC: [string, string, string][];
  }

  export interface Groth16PublicSignals extends Array<string> {}

  export interface Groth16FullProof {
    proof: Groth16Proof;
    publicSignals: Groth16PublicSignals;
  }

  export const groth16: {
    prove: (zkeyPath: string, witness: any) => Promise<Groth16FullProof>;
    fullProve: (witness: any, wasmPath: string, zkeyPath: string) => Promise<Groth16FullProof>;
    verify: (vk: Groth16VerificationKey, publicSignals: Groth16PublicSignals, proof: Groth16Proof) => Promise<boolean>;
    exportSolidityCallData: (proof: Groth16Proof, publicSignals: Groth16PublicSignals) => string;
  };

  export const powersOfTau: {
    newAccumulator: (curveName: string, numBits: number) => Promise<any>;
    contribute: (oldAccumulator: any, entropy: string) => Promise<any>;
    verify: (accumulator: any) => Promise<boolean>;
  };

  export const plonk: {
    setup: (r1cs: any, ptau: any) => Promise<any>;
    prove: (zkey: any, witness: any) => Promise<any>;
    verify: (vk: any, publicSignals: any, proof: any) => Promise<boolean>;
  };
} 