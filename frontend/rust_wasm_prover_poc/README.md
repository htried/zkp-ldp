# Rust + WASM prover POC

This is an in-repo attempt to expose a browser-callable prover from Rust.

## What this wraps

- `ark-circom-witnesscalc::proof_oneshot`
- `ark-circom-witnesscalc::proof_to_json`

The exported function `prove_groth16_json` accepts:

- `inputs_json` (`string`)
- proving key bytes (`Uint8Array`)
- witness graph bytes (`Uint8Array`)
- `r1cs` bytes (`Uint8Array`)

and returns proof JSON as a string.

## Build

From this folder:

```bash
wasm-pack build --target web --release
```

Output is generated in `pkg/`.
