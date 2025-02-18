import json
import os
import random

if not os.path.exists("input.json") or os.path.getsize("input.json") == 0:
    old_in = None
else:
    with open("input.json", "r") as in_json:
        old_in = json.load(in_json)

# Convert the IP to a value between 0 and 2**32 - 1
# Viewing IP as a base-255 number, little endian.
def ip_to_field_element(ip):
	parts = ip.split('.')
	assert(len(parts) == 4 and all(0 <= int(part) <= 255 for part in parts))
	felt = 0
	pow_of_256 = 1
	for part in parts.reverse():
		felt += int(part) * pow_of_256
		pow_of_256 *= 256
	return felt

if not old_in:
	print("No existing input found, creating new input")
	empty_ip = 0
	new_in = {
		"ipStrings": [empty_ip] * 5,
		"new_ip": empty_ip,
		"nonce": random.randint(1, 2**32),
		"is_challenge_response": "0"
	}
else:
	print("Existing input found, updating input")
	# Add validation for IPv4 format
	while True:
		ip = input("New IP address (IPv4 format xxx.xxx.xxx.xxx): ")
		# Basic IPv4 validation
		try:
			parts = ip.split('.')
			if len(parts) == 4 and all(0 <= int(part) <= 255 for part in parts):
				break
			print("Invalid IPv4 format. Please try again.")
		except (ValueError, AttributeError):
			print("Invalid IPv4 format. Please try again.")
	
	new_ip = ip_to_field_element(ip)
	test_challenge_response = input("Test challenge response? (0/1): ")
	test_challenge_response = int(test_challenge_response) 
	assert(test_challenge_response == 0 or test_challenge_response == 1)

	new_in = {
		"ipStrings": old_in['ipStrings'],
		"new_ip": new_ip,
		"nonce": random.randint(1, 2**32),
		"is_challenge_response": test_challenge_response
	}

with open("input.json", "w") as in_json:
	json.dump(new_in, in_json)
