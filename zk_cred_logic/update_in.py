import json
import os
import random
# import hashlib
# from ecdsa import SigningKey, SECP256k1
# from ecdsa.util import sigencode_string

if not os.path.exists("input.json") or os.path.getsize("input.json") == 0:
    old_in = None
else:
    with open("input.json", "r") as in_json:
        old_in = json.load(in_json)

def update_ip_strings(old_ips, new_ip, ip_exists):
	num_ips = len(old_ips)
	new_ips = old_ips.copy()
	
	if ip_exists:
		# Move existing IPs up
		for i in range(num_ips - 1, 0, -1):
			new_ips[i] = new_ips[i-1]
		# Add new IP at the end
		new_ips[num_ips - 1] = new_ip
	else:
		# Add new IP to the first available slot
		for i in range(num_ips):
			if new_ips[i] == "0" * 39:
				new_ips[i] = new_ip
				break
	
	return new_ips

def format_and_pad_ip(ip):
	# Pad IPv4 to 15 characters (xxx.xxx.xxx.xxx)
	return [ord(c) for c in ip.rjust(15, '0')]

if not old_in:
	print("No existing input found, creating new input")
	empty_ip = [ord('0')] * 15  # Create array of '0' characters for IPv4
	new_in = {
		"ipStrings": [empty_ip] * 5,
		"new_ip": empty_ip,
		"nonce": str(random.randint(1, 2**32)),
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
	
	new_ip = format_and_pad_ip(ip)
	test_challenge_response = input("Test challenge response? (0/1): ")

	new_in = {
		"ipStrings": old_in['ipStrings'],
		"new_ip": new_ip,
		"nonce": str(random.randint(1, 2**32)),
		"is_challenge_response": test_challenge_response
	}

with open("input.json", "w") as in_json:
	json.dump(new_in, in_json)
