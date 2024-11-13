import logging
import pickle
from typing import List, Optional
from geo_db_utils import HexagonNode
from typing import List


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

def get_hexagon_for_ip(ip_str: str, hexagon_nodes: List[HexagonNode]) -> Optional[HexagonNode]:
    logger.debug(f"Searching for hexagon containing IP: {ip_str}")
    # Convert IP string to integer for comparison
    ip_parts = [int(part) for part in ip_str.split('.')]
    ip_int = (ip_parts[0] << 24) + (ip_parts[1] << 16) + (ip_parts[2] << 8) + ip_parts[3]
    
    # Search through nodes to find containing hexagon
    for node in hexagon_nodes:
        for ip_range in node.ip_ranges:
            if ip_range.start_ip <= ip_int <= ip_range.end_ip:
                return node
                
    return None


if __name__ == "__main__":
    with open("geolocation_logic/hexagon_nodes.bin", "rb") as f:
        hexagon_nodes = pickle.load(f)

    with open("geolocation_logic/merkle_tree.bin", "rb") as f:
        merkle_root = f.read()

    ip = "128.84.95.234" # Cornell IP
    # ip = "210.138.184.59" # Random Tokyo IP that I found on the internet
    hexagon_node = get_hexagon_for_ip(ip, hexagon_nodes)
    if hexagon_node:
        logger.info(f"Test lookup result for {ip}: Hexagon {hexagon_node.h3_index}")
    else:
        logger.info(f"No hexagon found for IP {ip}")
