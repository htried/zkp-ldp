use ark_circom_witnesscalc::{proof_oneshot, proof_to_json, verify_proof_json};
use wasm_bindgen::prelude::*;

// Browser entrypoint for custom Rust+WASM proving.
// JS passes strings/bytes loaded from app assets or fetched at runtime.
#[wasm_bindgen]
pub fn prove_groth16_json(
    inputs_json: &str,
    pkey_bytes: &[u8],
    graph_bytes: &[u8],
    r1cs_bytes: &[u8],
) -> Result<String, JsValue> {
    console_error_panic_hook::set_once();

    let (proof, public_inputs) = proof_oneshot(inputs_json, pkey_bytes, graph_bytes, r1cs_bytes)
        .map_err(|e| JsValue::from_str(&format!("proof_oneshot failed: {e}")))?;

    proof_to_json(&proof, &public_inputs)
        .map_err(|e| JsValue::from_str(&format!("proof_to_json failed: {e}")))
}

#[wasm_bindgen]
pub fn verify_groth16_json(
    proof_json: &str,
    verification_key_json: &str,
) -> Result<bool, JsValue> {
    console_error_panic_hook::set_once();
    verify_proof_json(verification_key_json, proof_json)
        .map_err(|e| JsValue::from_str(&format!("verify_proof_json failed: {e}")))
}
