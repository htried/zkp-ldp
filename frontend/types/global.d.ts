declare module 'ffjavascript' {
  export class BigNumber {
    static from(value: number | string): BigNumber;
    toString(): string;
  }
}

interface Window {
  snarkjs: {
    groth16: {
      fullProve(input: any, wasm: string | ArrayBuffer, zkey: string | ArrayBuffer): Promise<{ proof: any, publicSignals: any }>;
      verify(vKey: any, publicSignals: any, proof: any): Promise<boolean>;
    };
  };
} 