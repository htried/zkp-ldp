from dataclasses import dataclass
from typing import List

@dataclass
class IPRange:
    start_ip: int
    end_ip: int
    lat: float
    lng: float
    country_code: str
    country: str
    province: str
    city: str

@dataclass
class HexagonNode:
    h3_index: str
    ip_ranges: List[IPRange]