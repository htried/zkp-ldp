# Test cases

### `cold_start.json`

Used to test the initial state creation scenario, when everything is initialized to 0. New state should equal old state and `challenge_failed` should be 1.

### `new_ip_challenge_fail_full.json`

Used to test the scenario where the input IP is a new IP address, the previously-seen IP list is full, and a challenge has not been passed. New state should equal old state and `challenge_failed` should be 1.

### `new_ip_challenge_fail_not_full.json`

Used to test the scenario where the input IP is a new IP address, the previously-seen IP list is not full, and a challenge has not been passed. New state should equal old state and `challenge_failed` should be 1.

### `new_ip_challenge_pass_full.json`

Used to test the scenario where the input IP is a new IP address, the previously-seen IP list is full, and a challenge *has* been passed. New state should not equal old state and `challenge_failed` should be 0.

### `new_ip_challenge_pass_not_full.json`

Used to test the scenario where the input IP is a new IP address, the previously-seen IP list is not full, and a challenge *has* been passed. New state should not equal old state and `challenge_failed` should be 0.

### `old_ip_full.json`

Used to test the scenario where the input IP is an old IP address, the previously-seen IP list is full. In this scenario, no need to pass a challenge. New state should not equal old state and `challenge_failed` should be 0.

### `old_ip_not_full.json`

Used to test the scenario where the input IP is an old IP address, the previously-seen IP list is not full. In this scenario, no need to pass a challenge. New state should not equal old state and `challenge_failed` should be 0.
