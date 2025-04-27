# Test cases

### `cold_start.json`

Used to test the initial state creation scenario, when everything is initialized to 0. Adding an IP and a geohash here should bypass the geohash distance checks, and the IP should be added to the first slot in the list.

### `add_new_ip_not_full.json`

Tests the scenario where a new IP is added to the state and an empty slot in the state is open.

### `add_new_ip_state_full.json`

Tests the scenario where a new IP is added to the state and the state is already full. The new IP should be put in the last slot of the state, and every other entry of the state should be pushed down by 1 entry.

### `add_old_ip_not_full.json`

Tests the scenario when an IP is added to the state when it's not empty, but the IP is already in the state. A new IP should not be added in this case.

### `add_old_ip_state_full.json`

Tests the scenario when an IP is added to the state when it's full and the IP is already in the state. The state's IP list should not change in this scenario.