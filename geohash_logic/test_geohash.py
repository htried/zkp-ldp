import json
import os
import subprocess
import pytest

# Cornell Tech coordinates with 6 decimal precision
CORNELL_TECH_LAT = 40756000 # 40.756 * 1e6
CORNELL_TECH_LNG = -73956000 # -73.956 * 1e6

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
    """Compile a Circom circuit to WASM and R1CS in the geohash_logic directory"""
    # Create output directory if it doesn't exist
    os.makedirs("geohash_logic/build", exist_ok=True)
    
    # Compile with output to build directory
    command = f"circom {circuit_path} --output geohash_logic/build -l geohash_logic/circomlib --r1cs --wasm --sym --c"
    run_command(command)

    return f"geohash_logic/build/{circuit_name}_js"

def generate_witness(js_dir, wasm_file, input_file, witness_file):
    """Generate witness for a circuit with the given input"""
    command = f"node {js_dir}/generate_witness.js {js_dir}/{wasm_file}.wasm {input_file} {witness_file}"
    run_command(command)

def export_witness_to_json(witness_file, json_file="geohash_logic/build/witness.json"):
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

def extract_circuit_outputs(witness_data):
    """Extract all outputs from the witness data with clear indexing"""
    # Circuit inputs are at indexes 1, 2, and 3
    INPUT_SIGNALS = 3
    
    # Extract original geohash data
    HASH_START = INPUT_SIGNALS + 1  # Index 4
    CHARS_START = HASH_START + 64   # Index 68
    
    # Extract neighbor data
    NEIGHBOR_START = CHARS_START + 12    # Index 80
    NEIGHBOR_CHARS_START = NEIGHBOR_START + 64  # Index 144
    
    return {
        'original_hash': extract_bits_from_witness(witness_data, HASH_START, 64),
        'original_chars': extract_bits_from_witness(witness_data, CHARS_START, 12),
        'neighbor_hash': extract_bits_from_witness(witness_data, NEIGHBOR_START, 64),
        'neighbor_chars': extract_bits_from_witness(witness_data, NEIGHBOR_CHARS_START, 12)
    }

# ----- Geohash Conversion Functions -----

base32_chars = "0123456789bcdefghjkmnpqrstuvwxyz"

def geohash_to_bits(geohash_str, num_bits):
    """Convert a base32 geohash string to its binary representation"""
    bits = []
    
    for char in geohash_str:
        value = base32_chars.index(char.lower())
        char_bits = [int(b) for b in bin(value)[2:].zfill(5)]
        bits.extend(char_bits)
    
    # Truncate or pad to the desired number of bits
    if len(bits) > num_bits:
        return bits[:num_bits]
    else:
        return bits + [0] * (num_bits - len(bits))
    
def bits_to_geohash(bits):
    """Convert a binary representation to a base32 geohash string"""
    geohash = ""
    for i in range(0, len(bits), 5):
        chunk = bits[i:i+5]
        value = sum(b * (2 ** (4-j)) for j, b in enumerate(chunk))
        geohash += base32_chars[value]
    return geohash

# ----- Test Class -----

class TestGeohash:
    @classmethod
    def setup_class(cls):
        """Compile all required circuits for testing into the geohash_logic directory"""
        # Compile circuits
        cls.geohash_test_js = compile_circuit("geohash_logic/geohash_test.circom", "geohash_test")
        cls.neighbor_test_js = compile_circuit("geohash_logic/neighbor_test.circom", "neighbor_test")
        
        # Input/output file paths
        cls.build_dir = "geohash_logic/build"
        os.makedirs(cls.build_dir, exist_ok=True)

    def test_geohash(self):
        """Test the proper geohash encoding with interval bisection"""
        
        input_data = {
            "lat": CORNELL_TECH_LAT,
            "lng": CORNELL_TECH_LNG
        }
        
        input_file = f"{self.build_dir}/geohash_input.json"
        witness_file = f"{self.build_dir}/geohash_witness.wtns"
        
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        # Generate and read witness
        generate_witness(self.geohash_test_js, "geohash_test", input_file, witness_file)
        witness_data = export_witness_to_json(witness_file)
        
        # Extract results using the clearer function
        outputs = extract_circuit_outputs(witness_data)
        bits = outputs['original_hash']
        
        # Print binary representation
        print(f"First 10 bits: {bits[:10]}")
        print(f"All bits: {''.join(map(str, bits))}")
                
        print(f"Geohash: {bits_to_geohash(bits)}")
        print("\nBit groups:")
        for i in range(0, 25, 5):
            chunk = bits[i:i+5]
            value = sum(b * (2 ** (4-j)) for j, b in enumerate(chunk))
            print(f"Bits {i}-{i+4}: {chunk} = {value} -> {base32_chars[value]}")

    def test_neighbors(self):
        """Test finding neighbors using proper geohash encoding"""
        
        # Test all directions
        directions = {
            0: "North",
            1: "Northeast",
            2: "East",
            3: "Southeast",
            4: "South",
            5: "Southwest",
            6: "West",
            7: "Northwest"
        }
        
        for direction, direction_name in directions.items():
            input_file = f"{self.build_dir}/neighbor_input_{direction}.json"
            witness_file = f"{self.build_dir}/neighbor_witness_{direction}.wtns"
            
            input_data = {
                "lat": CORNELL_TECH_LAT,
                "lng": CORNELL_TECH_LNG,
                "direction": direction
            }
            
            with open(input_file, "w") as f:
                json.dump(input_data, f)
            
            # Generate and read witness
            generate_witness(self.neighbor_test_js, "neighbor_test", input_file, witness_file)
            witness_data = export_witness_to_json(witness_file)
            
            # Extract results using the clearer function
            outputs = extract_circuit_outputs(witness_data)
            original_bits = outputs['original_hash']
            neighbor_bits = outputs['neighbor_hash']
            
            # Convert to base32
            original_geohash = bits_to_geohash(original_bits)
            neighbor_geohash = bits_to_geohash(neighbor_bits)
            
            print(f"\nDirection: {direction_name}")
            print(f"Original geohash: {original_geohash}")
            print(f"Neighbor geohash: {neighbor_geohash}")
            
            # Verify the geohashes are different
            assert original_geohash != neighbor_geohash, f"Neighbor in direction {direction_name} should be different"
            
            # Print first differing bit
            for i, (ob, nb) in enumerate(zip(original_bits, neighbor_bits)):
                if ob != nb:
                    print(f"First different bit at position {i}: {ob} vs {nb}")
                    break

if __name__ == "__main__":
    # pytest.main(["-xvs", "test_geohash.py"])
    test = TestGeohash()
    test.setup_class()
    print("testing normal geohash")
    test.test_geohash()
    print("testing neighbors")
    test.test_neighbors()

    print("✓ All tests completed successfully")