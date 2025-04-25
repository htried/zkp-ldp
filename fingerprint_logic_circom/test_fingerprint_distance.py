
import json
import os
import subprocess
import pytest

# ----- Helper Functions -----

def run_command(command):
    """Execute a shell command and return its output or raise an exception on error"""
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        shell=True
    )
    stdout, stderr = process.communicate()
    if process.returncode != 0:
        raise Exception(f"Command failed: {stderr.decode()}")
    return stdout.decode()

def compile_circuit(circuit_path, circuit_name):
    """Compile a Circom circuit to WASM and R1CS in the fingerprint_logic_circom directory"""
    # Create output directory if it doesn't exist
    os.makedirs("fingerprint_logic_circom/build", exist_ok=True)
    
    # Compile with output to build directory
    command = f"circom {circuit_path} --output fingerprint_logic_circom/build -l fingerprint_logic_circom/circomlib --r1cs --wasm --sym --c"
    run_command(command)

    return f"fingerprint_logic_circom/build/{circuit_name}_js"

def generate_witness(js_dir, wasm_file, input_file, witness_file):
    """Generate witness for a circuit with the given input"""
    command = f"node {js_dir}/generate_witness.js {js_dir}/{wasm_file}.wasm {input_file} {witness_file}"
    run_command(command)

def export_witness_to_json(witness_file, json_file="fingerprint_logic_circom/build/witness.json"):
    """Export a witness file to JSON format in the build directory"""
    # Make sure the output directory exists
    os.makedirs(os.path.dirname(json_file), exist_ok=True)
    
    run_command(f"snarkjs wtns export json {witness_file} {json_file}")
    with open(json_file, "r") as f:
        return json.load(f)

def extract_bits_from_witness(witness_data, start_idx, max_bits):
    """Extract bit values (0 or 1) from witness data"""
    bits = []
    for i in range(start_idx, len(witness_data)):
        if len(bits) < max_bits:
            if witness_data[i] in ['0', '1']:
                bits.append(int(witness_data[i]))
    return bits

# ----- Test Class -----

class TestFingerprintLogic:
    @classmethod
    def setup_class(cls):
        """Compile all required circuits for testing into the fingerprint_logic_circom directory"""
        # Compile circuits
        cls.fingerprint_main_js = compile_circuit("fingerprint_logic_circom/fingerprint_test.circom", "fingerprint_test")

        # Input/output file paths
        cls.build_dir = "fingerprint_logic_circom/build"
        os.makedirs(cls.build_dir, exist_ok=True)
    
    def test_no_similarity(self):
        """Basic sanity check for the similarity scores."""
        # Prepare input and output paths
        input_file = f"{self.build_dir}/debug_input.json"
        witness_file = f"{self.build_dir}/debug_witness.wtns"

        all_one_block = str(2**250 - 1)
        all_zero_block = str(0)


        input_data = {"hash1": [all_one_block, all_zero_block], 
                        "hash2": [all_zero_block, all_one_block]}
                
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Compile, generate and read witness
        debug_js = compile_circuit("fingerprint_logic_circom/fingerprint_test.circom", "fingerprint_test")
        generate_witness(debug_js, "fingerprint_test", input_file, witness_file)


        # Parse the symbol file to find the similarity result
        sym_file = f"{self.build_dir}/fingerprint_test.sym"
        similarity_score_index = 0
        
        if os.path.exists(sym_file):
            with open(sym_file, "r") as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 4:
                        idx = int(parts[0])
                        symbol = parts[3]
                        if ".similarity_score" in symbol:
                            similarity_score_index = idx

        witness_data = export_witness_to_json(witness_file)
        similarity_score = int(witness_data[similarity_score_index]) 

        assert(similarity_score == 0)

    def test_full_similarity(self):
        """Basic sanity check for the similarity scores."""
        # Prepare input and output paths
        input_file = f"{self.build_dir}/debug_input.json"
        witness_file = f"{self.build_dir}/debug_witness.wtns"

        all_one_block = str(2**250 - 1)
        all_zero_block = str(0)
        two_block = str(2)


        input_data = {"hash1": [all_one_block, two_block], 
                        "hash2": [all_one_block, two_block]}
                
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Compile, generate and read witness
        debug_js = compile_circuit("fingerprint_logic_circom/fingerprint_test.circom", "fingerprint_test")
        generate_witness(debug_js, "fingerprint_test", input_file, witness_file)


        # Parse the symbol file to find the similarity result
        sym_file = f"{self.build_dir}/fingerprint_test.sym"
        similarity_score_index = 0
        
        if os.path.exists(sym_file):
            with open(sym_file, "r") as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 4:
                        idx = int(parts[0])
                        symbol = parts[3]
                        if ".similarity_score" in symbol:
                            similarity_score_index = idx

        witness_data = export_witness_to_json(witness_file)
        similarity_score = int(witness_data[similarity_score_index]) 

        assert(similarity_score == 500)


if __name__ == "__main__":
    pytest.main(["-xvs", "test_fingerprint_distance.py"])
