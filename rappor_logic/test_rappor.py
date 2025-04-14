
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
    """Compile a Circom circuit to WASM and R1CS in the rappor_logic directory"""
    # Create output directory if it doesn't exist
    os.makedirs("rappor_logic/build", exist_ok=True)
    
    # Compile with output to build directory
    command = f"circom {circuit_path} --output rappor_logic/build -l rappor_logic/circomlib --r1cs --wasm --sym --c"
    run_command(command)

    return f"rappor_logic/build/{circuit_name}_js"

def generate_witness(js_dir, wasm_file, input_file, witness_file):
    """Generate witness for a circuit with the given input"""
    command = f"node {js_dir}/generate_witness.js {js_dir}/{wasm_file}.wasm {input_file} {witness_file}"
    run_command(command)

def export_witness_to_json(witness_file, json_file="rappor_logic/build/witness.json"):
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

class TestRappor:
    @classmethod
    def setup_class(cls):
        """Compile all required circuits for testing into the rappor_logic directory"""
        # Compile circuits
        cls.rappor_main_js = compile_circuit("rappor_logic/rappor_main.circom", "rappor_main")

        # Input/output file paths
        cls.build_dir = "rappor_logic/build"
        os.makedirs(cls.build_dir, exist_ok=True)
    
    def test_base_case(self):
        """Test a minimal case where all randomness is all 1's (do nothing) and we just use the old PRR"""
        # Prepare input and output paths
        input_file = f"{self.build_dir}/debug_input.json"
        witness_file = f"{self.build_dir}/debug_witness.wtns"

        all_one_randomness = str(2**250 - 1)


        # Setting some values to random keyboard smashes to make sure the test isn't returning the wrong data
        input_data = {"f_randomness": all_one_randomness, 
                        "p_randomness": all_one_randomness, 
                        "q_randomness": "0", 
                        "old_bloom_state": "32769", 
                        "old_prr_state": "123",
                        "new_value": "9999312313993131",
                        "add_new_value": "0"}
                
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Compile, generate and read witness
        debug_js = compile_circuit("rappor_logic/rappor_main.circom", "rappor_main")
        generate_witness(debug_js, "rappor_main", input_file, witness_file)


        # Parse the symbol file to find the rappor response
        sym_file = f"{self.build_dir}/rappor_main.sym"
        response_index = 0
        
        if os.path.exists(sym_file):
            with open(sym_file, "r") as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 4:
                        idx = int(parts[0])
                        symbol = parts[3]
                        if "rappor_response" in symbol:
                            response_index = idx

        witness_data = export_witness_to_json(witness_file)
        rappor_response = int(witness_data[response_index]) 

        assert(rappor_response == 123)

    def test_q_randomness(self):
        """Test that the q randomness flips the 0 bits in the PRR"""
        # Prepare input and output paths
        input_file = f"{self.build_dir}/debug_input.json"
        witness_file = f"{self.build_dir}/debug_witness.wtns"

        all_one_randomness = str(2**250 - 1)


        # Setting some values to random keyboard smashes to make sure the test isn't returning the wrong data
        input_data = {"f_randomness": all_one_randomness, 
                        "p_randomness": all_one_randomness, 
                        "q_randomness": "0", 
                        "old_bloom_state": "32769", 
                        # State is set to all ones, so q randomness will flip these
                        "old_prr_state": "65535",
                        "new_value": "9999312313993131",
                        "add_new_value": "0"}
                
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Compile, generate and read witness
        debug_js = compile_circuit("rappor_logic/rappor_main.circom", "rappor_main")
        generate_witness(debug_js, "rappor_main", input_file, witness_file)


        # Parse the symbol file to find the rappor response
        sym_file = f"{self.build_dir}/rappor_main.sym"
        response_index = 0
        
        if os.path.exists(sym_file):
            with open(sym_file, "r") as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 4:
                        idx = int(parts[0])
                        symbol = parts[3]
                        if "rappor_response" in symbol:
                            response_index = idx

        witness_data = export_witness_to_json(witness_file)
        rappor_response = int(witness_data[response_index]) 

        assert(rappor_response == 65535)

    def test_p_randomness(self):
        """Test that the p randomness flips 1 bits in the PRR"""
        # Prepare input and output paths
        input_file = f"{self.build_dir}/debug_input.json"
        witness_file = f"{self.build_dir}/debug_witness.wtns"

        all_one_randomness = str(2**250 - 1)


        # Setting some values to random keyboard smashes to make sure the test isn't returning the wrong data
        input_data = {"f_randomness": all_one_randomness, 
                        "p_randomness": "0", 
                        "q_randomness": all_one_randomness, 
                        "old_bloom_state": "32769", 
                        "old_prr_state": "0",
                        "new_value": "9999312313993131",
                        "add_new_value": "0"}
                
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Compile, generate and read witness
        debug_js = compile_circuit("rappor_logic/rappor_main.circom", "rappor_main")
        generate_witness(debug_js, "rappor_main", input_file, witness_file)


        # Parse the symbol file to find the rappor response
        sym_file = f"{self.build_dir}/rappor_main.sym"
        response_index = 0
        
        if os.path.exists(sym_file):
            with open(sym_file, "r") as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 4:
                        idx = int(parts[0])
                        symbol = parts[3]
                        if "rappor_response" in symbol:
                            response_index = idx

        witness_data = export_witness_to_json(witness_file)
        rappor_response = int(witness_data[response_index]) 

        assert(rappor_response == 65535)

    def test_bloom_filter_insertion(self):
        """Test that adding a value to the bloom filter flips num_hashes (2) bits."""
        # Prepare input and output paths
        input_file = f"{self.build_dir}/debug_input.json"
        witness_file = f"{self.build_dir}/debug_witness.wtns"

        all_one_randomness = str(2**250 - 1)


        # Setting some values to random keyboard smashes to make sure the test isn't returning the wrong data
        input_data = {"f_randomness": all_one_randomness, 
                        "p_randomness": all_one_randomness, 
                        # q_randomness needs to be zero because 
                        "q_randomness": "0", 
                        "old_bloom_state": "0", 
                        "old_prr_state": "32001",
                        "new_value": "12345678",
                        "add_new_value": "1"}
                
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Compile, generate and read witness
        debug_js = compile_circuit("rappor_logic/rappor_main.circom", "rappor_main")
        generate_witness(debug_js, "rappor_main", input_file, witness_file)


        # Parse the symbol file to find the rappor response
        sym_file = f"{self.build_dir}/rappor_main.sym"
        response_index = 0
        
        if os.path.exists(sym_file):
            with open(sym_file, "r") as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 4:
                        idx = int(parts[0])
                        symbol = parts[3]
                        if "rappor_response" in symbol:
                            response_index = idx

        witness_data = export_witness_to_json(witness_file)
        rappor_response = int(witness_data[response_index]) 

        assert(bin(rappor_response).count('1') == 2)

    def test_f_randomness(self):
        """Test that the f parameter flips bits correctly."""
        # Prepare input and output paths
        input_file = f"{self.build_dir}/debug_input.json"
        witness_file = f"{self.build_dir}/debug_witness.wtns"

        all_one_randomness = str(2**250 - 1)


        # Setting some values to random keyboard smashes to make sure the test isn't returning the wrong data
        input_data = {"f_randomness": "0", 
                        "p_randomness": all_one_randomness, 
                        # q_randomness needs to be zero because 
                        "q_randomness": "0", 
                        "old_bloom_state": "0", 
                        "old_prr_state": "32001",
                        "new_value": "12345678",
                        "add_new_value": "1"}
                
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Compile, generate and read witness
        debug_js = compile_circuit("rappor_logic/rappor_main.circom", "rappor_main")
        generate_witness(debug_js, "rappor_main", input_file, witness_file)


        # Parse the symbol file to find the rappor response
        sym_file = f"{self.build_dir}/rappor_main.sym"
        response_index = 0
        
        if os.path.exists(sym_file):
            with open(sym_file, "r") as f:
                for line in f:
                    parts = line.strip().split(",")
                    if len(parts) >= 4:
                        idx = int(parts[0])
                        symbol = parts[3]
                        if "rappor_response" in symbol:
                            response_index = idx

        witness_data = export_witness_to_json(witness_file)
        rappor_response = int(witness_data[response_index]) 

        assert(rappor_response == 0)


if __name__ == "__main__":
    pytest.main(["-xvs", "test_rappor.py"])
