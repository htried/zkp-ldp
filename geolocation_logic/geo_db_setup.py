import h3
import csv
import ipaddress
from collections import defaultdict
from typing import Dict, List, Tuple
import hashlib
import logging
import pickle
from geo_db_utils import IPRange, HexagonNode
from concurrent.futures import ProcessPoolExecutor, as_completed
import numpy as np

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    force=True
)
logger = logging.getLogger(__name__)

min_resolution = 4
max_resolution = 9
target_density = 512

    
def ip_string_to_int(ip: str) -> int:
    return int(ipaddress.IPv4Address(ip))

def add_noise_within_hexagon(lat: float, lng: float, hex_id: str) -> Tuple[float, float]:
    """Add random noise to coordinates while ensuring they stay within the hexagon boundary"""
    boundary = h3.cell_to_boundary(hex_id)
    
    # Convert boundary points to numpy array for easier computation
    boundary = np.array(boundary)
    
    # Calculate center and max distance from center to any vertex
    center = np.mean(boundary, axis=0)
    max_dist = np.max(np.linalg.norm(boundary - center, axis=1))
    
    # Generate random angle and radius (using sqrt for even distribution)
    angle = np.random.uniform(0, 2 * np.pi)
    # Using full max_dist to allow points to spread all the way to the edges
    radius = max_dist * np.sqrt(np.random.uniform(0, 1))
    
    # Convert polar coordinates to lat/lng offsets
    # Removed the 111111 scaling factor since max_dist is already in degrees
    noise_lat = radius * np.cos(angle)
    noise_lng = radius * np.sin(angle) / np.cos(np.radians(lat))
    
    return lat + noise_lat, lng + noise_lng

def process_ip_batch(rows: List[List[str]]) -> List[IPRange]:
    """Process a batch of IP data rows in parallel"""
    ip_ranges = []
    for row in rows:
        try:
            # Get base hexagon for this location
            base_hex = h3.latlng_to_cell(float(row[6]), float(row[7]), min_resolution)
            # Add noise to coordinates
            noisy_lat, noisy_lng = add_noise_within_hexagon(
                float(row[6]), 
                float(row[7]), 
                base_hex
            )
            
            ip_range = IPRange(
                start_ip=int(row[0]),
                end_ip=int(row[1]),
                country_code=row[2],
                country=row[3],
                province=row[4],
                city=row[5],
                lat=noisy_lat,
                lng=noisy_lng
            )
            ip_ranges.append(ip_range)
        except (ValueError, IndexError) as e:
            continue
    return ip_ranges

def load_ip_data(filename: str) -> List[IPRange]:
    logger.info(f"Loading IP data from {filename}")
    
    # Read all rows first
    with open(filename, 'r') as f:
        reader = csv.reader(f)
        all_rows = list(reader)
    
    # Split into batches
    batch_size = 10000  # Adjust based on your system
    batches = [all_rows[i:i + batch_size] for i in range(0, len(all_rows), batch_size)]
    logger.info(f"Split data into {len(batches)} batches")
    
    # Process batches in parallel
    ip_ranges = []
    error_count = 0
    with ProcessPoolExecutor() as executor:
        future_to_batch = {executor.submit(process_ip_batch, batch): i 
                         for i, batch in enumerate(batches)}
        
        for future in as_completed(future_to_batch):
            batch_num = future_to_batch[future]
            try:
                batch_results = future.result()
                ip_ranges.extend(batch_results)
                if batch_num % 10 == 0:  # Log progress every 10 batches
                    logger.info(f"Processed batch {batch_num}/{len(batches)}")
            except Exception as e:
                error_count += 1
                logger.warning(f"Failed to process batch {batch_num}: {e}")
    
    logger.info(f"Loaded {len(ip_ranges)} IP ranges successfully. Encountered {error_count} batch errors.")
    return ip_ranges

def calculate_ip_density(ip_ranges: List[IPRange], resolution: int) -> Dict[str, int]:
    """Calculate IP density per hexagon at given resolution"""
    density_map = defaultdict(int)
    
    for ip_range in ip_ranges:
        hex_id = h3.latlng_to_cell(ip_range.lat, ip_range.lng, resolution)
        # Count number of IPs in range
        density_map[hex_id] += ip_range.end_ip - ip_range.start_ip + 1
        
    return density_map

def _recursive_resolution(hex_id: str, current_res: int, hex_ip_ranges: List[IPRange], 
                         max_resolution: int, target_density: int) -> Dict[str, int]:
    # First, check if we have any IP ranges to process
    if not hex_ip_ranges:
        return {}

    # Calculate density for current hexagon by only counting IPs that fall within this hexagon
    density = 0
    hex_ip_ranges = [ip_range for ip_range in hex_ip_ranges 
                    if h3.latlng_to_cell(ip_range.lat, ip_range.lng, current_res) == hex_id]
    
    for ip_range in hex_ip_ranges:
        ip_count = ip_range.end_ip - ip_range.start_ip + 1
        density += ip_count
    
    # Base cases: target density reached or max resolution
    if density <= target_density or current_res >= max_resolution:
        results = {}
        for ip_range in hex_ip_ranges:
            final_hex = h3.latlng_to_cell(ip_range.lat, ip_range.lng, current_res)
            results[final_hex] = current_res
        return results
        
    # Recursive case: split into child hexagons
    all_results = {}
    
    # Group IP ranges by child hexagon
    child_ip_ranges = defaultdict(list)
    for ip_range in hex_ip_ranges:
        child_hex = h3.latlng_to_cell(ip_range.lat, ip_range.lng, current_res + 1)
        child_ip_ranges[child_hex].append(ip_range)
    
    # Process each child hexagon with its relevant IP ranges
    for child_hex, ranges in child_ip_ranges.items():
        child_results = _recursive_resolution(
            child_hex, 
            current_res + 1, 
            ranges,
            max_resolution,
            target_density
        )
        all_results.update(child_results)
    
    return all_results

def determine_optimal_resolution(ip_ranges: List[IPRange], target_density: int = 1024) -> Dict[str, int]:
    logger.info(f"Determining optimal resolution with target density of {target_density}")
    
    # Pre-group IP ranges by base hexagon
    base_hex_groups = defaultdict(list)
    for ip_range in ip_ranges:
        base_hex = h3.latlng_to_cell(ip_range.lat, ip_range.lng, min_resolution)
        base_hex_groups[base_hex].append(ip_range)
    
    logger.info(f"Grouped IPs into {len(base_hex_groups)} base hexagons")
    
    # Process each base hexagon
    optimal_resolutions = {}
    for base_hex, hex_ip_ranges in base_hex_groups.items():
        results = _recursive_resolution(
            base_hex,
            min_resolution,
            hex_ip_ranges,
            max_resolution,
            target_density
        )
        optimal_resolutions.update(results)
    
    logger.info(f"Calculated optimal resolutions for {len(optimal_resolutions)} hexagons")
    return optimal_resolutions

def create_merkle_tree(hexagon_nodes: List[HexagonNode]) -> bytes:
    """Create a Merkle tree from hexagon nodes"""
    if not hexagon_nodes:
        return hashlib.sha256(b'').digest()
    
    # Hash leaf nodes
    leaf_hashes = []
    for node in hexagon_nodes:
        # Create deterministic string representation of IP ranges
        content = ''.join(f"{r.start_ip}-{r.end_ip}" for r in node.ip_ranges)
        content = f"{node.h3_index}:{content}"
        leaf_hashes.append(hashlib.sha256(content.encode()).digest())
    
    # Build tree levels
    current_level = leaf_hashes
    while len(current_level) > 1:
        next_level = []
        for i in range(0, len(current_level), 2):
            left = current_level[i]
            right = current_level[i + 1] if i + 1 < len(current_level) else left
            combined = hashlib.sha256(left + right).digest()
            next_level.append(combined)
        current_level = next_level
    
    return current_level[0]

def build_adaptive_ip_mapping(filename: str, target_density: int = 1024) -> Tuple[List[HexagonNode], bytes]:
    logger.info(f"Building adaptive IP mapping from {filename}")
    
    # Load IP data
    ip_ranges = load_ip_data(filename)
    logger.info(f"Loaded {len(ip_ranges)} IP ranges")
    
    # Determine optimal resolutions for different areas
    optimal_resolutions = determine_optimal_resolution(ip_ranges, target_density)
    logger.info(f"Resolution distribution:")
    resolution_counts = defaultdict(int)
    for hex_id, res in optimal_resolutions.items():
        resolution_counts[res] += 1
    for res, count in sorted(resolution_counts.items()):
        logger.info(f"Resolution {res}: {count} hexagons")
    
    # Group IPs into appropriate hexagons
    hexagon_map = defaultdict(list)
    
    for ip_range in ip_ranges:
        # Get base hexagon
        possible_hexes = [h3.latlng_to_cell(ip_range.lat, ip_range.lng, res) for res in range(min_resolution, max_resolution+1)]
        
        # Get the target resolution for this base hexagon
        final_hex = None
        for i in range(0, len(possible_hexes)):
            target_res = optimal_resolutions.get(possible_hexes[i])
            if target_res is not None:
                final_hex = possible_hexes[i]
            
        if final_hex is None:
            final_hex = possible_hexes[0]
            
        hexagon_map[final_hex].append(ip_range)
    
    logger.info(f"Grouped IPs into {len(hexagon_map)} hexagons")
    resolution_counts = defaultdict(int)
    for hex_id in hexagon_map.keys():
        res = h3.get_resolution(hex_id)
        resolution_counts[res] += 1
    logger.info("Final hexagon resolution distribution:")
    for res, count in sorted(resolution_counts.items()):
        logger.info(f"Resolution {res}: {count} hexagons")
    
    # Create hexagon nodes
    hexagon_nodes = [
        HexagonNode(h3_index=hex_id, ip_ranges=ranges)
        for hex_id, ranges in hexagon_map.items()
    ]
    
    # Build Merkle tree
    logger.info("Building Merkle tree")
    merkle_root = create_merkle_tree(hexagon_nodes)
    logger.info("Merkle tree construction complete")
    
    return hexagon_nodes, merkle_root


if __name__ == "__main__":
    logger.info("Starting IP mapping process")
    hexagon_nodes, merkle_root = build_adaptive_ip_mapping("geolocation_logic/IP2LOCATION-LITE-DB5.CSV", target_density=target_density)
    
    # Write merkle tree to disk
    with open("geolocation_logic/merkle_tree.bin", "wb") as f:
        f.write(merkle_root)

    with open("geolocation_logic/hexagon_nodes.bin", "wb") as f:
        pickle.dump(hexagon_nodes, f)
    
    logger.info("Wrote merkle tree and hexagon nodes to disk")
    