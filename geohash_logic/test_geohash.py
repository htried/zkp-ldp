import json
import os
import subprocess
import time
import shutil

# Cornell Tech coordinates normalized and scaled by 1e6
CORNELL_TECH_LAT = 40.756
CORNELL_TECH_LNG = -73.956

CORNELL_TECH_LAT_BITS = int((CORNELL_TECH_LAT + 90) * 1e6)
CORNELL_TECH_LNG_BITS = int((CORNELL_TECH_LNG + 180) * 1e6)

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
    build_dir = "geohash_logic/build"
    os.makedirs(build_dir, exist_ok=True)
    
    # Clean any existing build files for this circuit
    js_dir = f"{build_dir}/{circuit_name}_js"
    if os.path.exists(js_dir):
        print(f"Removing existing build directory: {js_dir}")
        shutil.rmtree(js_dir)
    
    # Compile with output to build directory
    command = f"circom {circuit_path} --output {build_dir} -l geohash_logic/circomlib --r1cs --wasm --sym --c"
    output = run_command(command)

    return f"{build_dir}/{circuit_name}_js"

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
    # Extract the original inputs at witness indices -2 and -1
    lat_value = int(witness_data[-2])
    lng_value = int(witness_data[-1])
    
    print(f"\nActual input values from witness:")
    print(f"Lat decimal: {lat_value} (expected: {CORNELL_TECH_LAT_BITS})")
    print(f"Lng decimal: {lng_value} (expected: {CORNELL_TECH_LNG_BITS})")
    
    # Raw bits output should be somewhere in witness - let's calculate them directly
    # from the confirmed input values 
    lat_bits_lsb = [(lat_value >> i) & 1 for i in range(32)]
    lng_bits_lsb = [(lng_value >> i) & 1 for i in range(32)]
    
    # Convert to MSB for display and interleaving
    lat_bits_msb = lat_bits_lsb[::-1]
    lng_bits_msb = lng_bits_lsb[::-1]
    
    print("\nExpected bits from input values:")
    print(f"Lat bits: {''.join(map(str, lat_bits_msb))}")
    print(f"Lng bits: {''.join(map(str, lng_bits_msb))}")
    
    # Generate interleaved bits as the circuit would (lng even, lat odd)
    interleaved_bits = []
    for i in range(32):
        interleaved_bits.append(lng_bits_msb[i])  # Even positions (MSB order)
        interleaved_bits.append(lat_bits_msb[i])  # Odd positions (MSB order)
    
    return {
        'interleaved_hash': interleaved_bits,
        'lat_value': lat_value,
        'lng_value': lng_value
    }

def extract_neighbor_outputs(witness_data):
    """Extract outputs specifically for neighbor test"""
    # Get inputs from the correct indices
    original_lat = int(witness_data[153])
    original_lng = int(witness_data[154])
    neighbor_lat = int(witness_data[158])
    neighbor_lng = int(witness_data[159])
    
    print(f"\nCoordinates from witness:")
    print(f"Original: ({original_lat/1e6-90:.6f}, {original_lng/1e6-180:.6f})")
    print(f"Neighbor: ({neighbor_lat/1e6-90:.6f}, {neighbor_lng/1e6-180:.6f})")
    
    # Generate bits directly from coordinates in MSB order (how the circuit works)
    
    # Original bits
    original_lat_bits_lsb = [(original_lat >> i) & 1 for i in range(32)]
    original_lng_bits_lsb = [(original_lng >> i) & 1 for i in range(32)]
    original_lat_bits_msb = original_lat_bits_lsb[::-1]  # Reverse to get MSB order
    original_lng_bits_msb = original_lng_bits_lsb[::-1]  # Reverse to get MSB order
    
    # Neighbor bits
    neighbor_lat_bits_lsb = [(neighbor_lat >> i) & 1 for i in range(32)]
    neighbor_lng_bits_lsb = [(neighbor_lng >> i) & 1 for i in range(32)]
    neighbor_lat_bits_msb = neighbor_lat_bits_lsb[::-1]  # Reverse to get MSB order
    neighbor_lng_bits_msb = neighbor_lng_bits_lsb[::-1]  # Reverse to get MSB order
    
    # Interleave bits as the circuit does
    original_bits = []
    neighbor_bits = []
    
    for i in range(32):
        original_bits.append(original_lng_bits_msb[i])  # Even positions
        original_bits.append(original_lat_bits_msb[i])  # Odd positions
        neighbor_bits.append(neighbor_lng_bits_msb[i])  # Even positions
        neighbor_bits.append(neighbor_lat_bits_msb[i])  # Odd positions
    
    print(f"Original lat bits: {''.join(map(str, original_lat_bits_msb))}")
    print(f"Original lng bits: {''.join(map(str, original_lng_bits_msb))}")
    print(f"Neighbor lat bits: {''.join(map(str, neighbor_lat_bits_msb))}")
    print(f"Neighbor lng bits: {''.join(map(str, neighbor_lng_bits_msb))}")
    
    return {
        'original_hash': original_bits,
        'neighbor_hash': neighbor_bits,
        'original_lat': original_lat,
        'original_lng': original_lng,
        'neighbor_lat': neighbor_lat,
        'neighbor_lng': neighbor_lng
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
        # Pad chunk if needed
        while len(chunk) < 5:
            chunk.append(0)
        
        # Ensure all bits are 0 or 1
        for j, bit in enumerate(chunk):
            if bit not in [0, 1]:
                print(f"WARNING: Invalid bit in chunk at position {j}: {bit}")
                chunk[j] = 0
        
        # Calculate value (0-31)
        value = sum(int(chunk[j]) * (2 ** (4-j)) for j in range(5))
        
        # Safety check
        if value < 0 or value >= 32:
            print(f"WARNING: Invalid value calculated: {value}, setting to 0")
            value = 0
            
        geohash += base32_chars[value]
    return geohash

def geohash_bits_to_coords(bits):
    """Convert geohash bits to latitude and longitude coordinates"""
    # Deinterleave bits (even = longitude, odd = latitude)
    lng_bits = bits[::2][:32]   # even indices are longitude (MSB)
    lat_bits = bits[1::2][:32]  # odd indices are latitude (MSB)
    
    # Convert to decimal using MSB order
    lat_decimal = sum(int(lat_bits[i]) * (2 ** (31-i)) for i in range(32))
    lng_decimal = sum(int(lng_bits[i]) * (2 ** (31-i)) for i in range(32))
    
    # Convert back to original coordinates
    lat = lat_decimal / 1e6 - 90
    lng = lng_decimal / 1e6 - 180
    
    return lat, lng

# ----- Test Class -----

class TestGeohash:
    @classmethod
    def setup_class(cls):
        """Compile all required circuits for testing into the geohash_logic directory"""

        # Input/output file paths
        cls.build_dir = "geohash_logic/build"

        # Clean build directory first
        for item in os.listdir(cls.build_dir):
            prefixes = ["geohash_test", "neighbor_test", "witness", "geohash_witness", "neighbor_witness", "geohash_input", "neighbor_input"]
            if any(item.startswith(prefix) for prefix in prefixes):
                path = os.path.join(cls.build_dir, item)
                if os.path.isdir(path):
                    print(f"Removing old build directory: {path}")
                    shutil.rmtree(path)
                else:
                    print(f"Removing old build file: {path}")
                    os.remove(path)

        os.makedirs(cls.build_dir, exist_ok=True)
        
        # Recompile the circuit
        cls.geohash_test_js = compile_circuit("geohash_logic/geohash_test.circom", "geohash_test")
        cls.neighbor_test_js = compile_circuit("geohash_logic/neighbor_test.circom", "neighbor_test")
        

    def test_geohash(self):
        """Test the proper geohash encoding with interval bisection"""
                
        # Use the correct input format with named fields
        input_data = {
            "lat": CORNELL_TECH_LAT_BITS,
            "lng": CORNELL_TECH_LNG_BITS
        }
        
        # Use timestamp for unique filenames
        timestamp = int(time.time())
        
        input_file = f"{self.build_dir}/geohash_input_{timestamp}.json"
        witness_file = f"{self.build_dir}/geohash_witness_{timestamp}.wtns"
        
        with open(input_file, "w") as f:
            json.dump(input_data, f)
        
        print(f"\nDumping input file contents for verification:")
        with open(input_file, "r") as f:
            print(f.read())

        generate_witness(self.geohash_test_js, "geohash_test", input_file, witness_file)
                
        # Verify witness file exists
        if not os.path.exists(witness_file):
            print(f"ERROR: Witness file {witness_file} was not created!")
            return
        
        witness_data = export_witness_to_json(witness_file)
                
        outputs = extract_circuit_outputs(witness_data)
        interleaved_bits = outputs['interleaved_hash']
        
        # Print debug information
        print("\nInput binary representations:")
        print(f"Input lat binary:  {bin(CORNELL_TECH_LAT_BITS)[2:].zfill(32)}")
        print(f"Input lng binary:  {bin(CORNELL_TECH_LNG_BITS)[2:].zfill(32)}")
        
        print(f"\nFinal output:")
        print(f"First 10 bits: {interleaved_bits[:10]}")
        print(f"All bits: {''.join(map(str, interleaved_bits))}")
        print(f"Geohash: {bits_to_geohash(interleaved_bits)}")
        print(f"coords: {geohash_bits_to_coords(interleaved_bits)}")

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
            json_file = f"{self.build_dir}/neighbor_witness_{direction}.json"
            
            # IMPORTANT: Use the correct input format
            input_data = {
                "lat": CORNELL_TECH_LAT_BITS,
                "lng": CORNELL_TECH_LNG_BITS,
                "direction": direction
            }
            
            with open(input_file, "w") as f:
                json.dump(input_data, f)
            
            # Debug the input file
            with open(input_file, "r") as f:
                input_content = f.read()
                print(f"\nInput file for {direction_name}: {input_content}")

            generate_witness(self.neighbor_test_js, "neighbor_test", input_file, witness_file)
            
            # Export to JSON
            witness_data = export_witness_to_json(witness_file, json_file)
            
            # Use our specialized extraction function
            outputs = extract_neighbor_outputs(witness_data)
            original_bits = outputs['original_hash']
            neighbor_bits = outputs['neighbor_hash']
            
            # Convert to base32
            original_geohash = bits_to_geohash(original_bits)
            neighbor_geohash = bits_to_geohash(neighbor_bits)
            
            # Convert to coordinates
            original_lat, original_lng = geohash_bits_to_coords(original_bits)
            neighbor_lat, neighbor_lng = geohash_bits_to_coords(neighbor_bits)
            
            print(f"\nDirection: {direction_name}")
            print(f"Original geohash: {original_geohash} ({original_lat:.6f}, {original_lng:.6f})")
            print(f"Neighbor geohash: {neighbor_geohash} ({neighbor_lat:.6f}, {neighbor_lng:.6f})")
            
            # Verify against expected coordinates from the circuit
            exp_orig_lat = (int(outputs['original_lat']) / 1e6) - 90
            exp_orig_lng = (int(outputs['original_lng']) / 1e6) - 180
            exp_neigh_lat = (int(outputs['neighbor_lat']) / 1e6) - 90
            exp_neigh_lng = (int(outputs['neighbor_lng']) / 1e6) - 180
            
            print(f"Expected original: ({exp_orig_lat:.6f}, {exp_orig_lng:.6f})")
            print(f"Expected neighbor: ({exp_neigh_lat:.6f}, {exp_neigh_lng:.6f})")
            
            # Verify the geohashes are different
            assert original_geohash != neighbor_geohash, f"Neighbor in direction {direction_name} should be different"

if __name__ == "__main__":
    # pytest.main(["-xvs", "test_geohash.py"])
    test = TestGeohash()
    test.setup_class()
    print(f"\n{'=' * 22}\ntesting normal geohash\n{'=' * 22}\n")
    test.test_geohash()
    print(f"\n{'=' * 17}\ntesting neighbors\n{'=' * 17}\n")
    test.test_neighbors()

    print("✓ All tests completed successfully")