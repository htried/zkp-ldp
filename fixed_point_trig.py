"""
Fixed-point trigonometric functions for geolocation distance calculations.

Adapted from C code written by Joe Tsai <joetsai@digital-static.net>
Original code dedicated to the public domain.

This module provides fixed-point sine and cosine approximations that can be
used for geolocation distance calculations (e.g., Haversine formula) where
floating-point operations need to be avoided or where fixed-point arithmetic
is required for compatibility with zero-knowledge proof circuits.
"""

import math


def fixed_to_float(value: int, scale: int) -> float:
    """Convert a fixed-point value to a floating-point value.
    
    Args:
        value: Fixed-point integer value
        scale: Scale factor (number of fractional bits)
        
    Returns:
        Floating-point representation of the fixed-point value
    """
    return float(value) / (1 << scale)


def float_to_fixed(value: float, scale: int) -> int:
    """Convert a floating-point value to a fixed-point value.
    
    Args:
        value: Floating-point value to convert
        scale: Scale factor (number of fractional bits)
        
    Returns:
        Fixed-point integer representation
        
    Raises:
        ValueError: If value is NaN or Inf
    """
    if math.isnan(value) or math.isinf(value):
        raise ValueError(f"Cannot convert NaN or Inf to fixed-point: {value}")
    return int((value * (1 << scale)) + 0.5)


def clamp_overflow(value: int, width: int) -> int:
    """Clamp an overflowed fixed-point two's complement value.
    
    Args:
        value: The value to clamp
        width: Bit width for the fixed-point representation
        
    Returns:
        Clamped value within the valid range
    """
    # Mask to width bits to get the actual value
    value_mask = (1 << width) - 1
    sign_bit_mask = 1 << (width - 1)
    max_positive = (1 << (width - 1)) - 1
    min_negative = -(1 << (width - 1))
    
    # Mask to width bits (unsigned)
    value_masked = value & value_mask
    
    # Convert to signed value
    if value_masked >= sign_bit_mask:
        # Sign bit is set, this is negative in two's complement
        value_signed = value_masked - (1 << width)
    else:
        # Positive number
        value_signed = value_masked
    
    # Check for overflow using the C logic
    # We need to check if bits above width-1 differ from the sign bit
    # For a properly clamped value, all bits above width-1 should match the sign bit
    # Extract the bit at position width and the sign bit at width-1
    if value_signed >= 0:
        high0 = (value_signed >> width) & 0x01
        high1 = (value_signed >> (width - 1)) & 0x01
        if high0 ^ high1:  # Overflow detected
            if high0:
                value_signed = min_negative
            else:
                value_signed = max_positive
    else:
        # For negative numbers in Python, right shift extends sign bit
        # So we check if the value is within range by checking the magnitude
        if value_signed < min_negative:
            value_signed = min_negative
    
    # Final clamp to valid range (safety check)
    if value_signed > max_positive:
        value_signed = max_positive
    elif value_signed < min_negative:
        value_signed = min_negative
    
    return value_signed


def sine(value: int) -> int:
    """
    Fixed-point sine approximation. Normalized for an input domain of [0,1)
    instead of the usual domain of [0,2*PI).
    
    Uses Taylor series approximation for sine centered at zero:
        sine(2*PI*x) = 0 + (2*PI*x)^1/1! - (2*PI*x)^3/3!
                     + (2*PI*x)^5/5! - (2*PI*x)^7/7!
                   = k_1*x^1 - k_3*x^3 + k_5*x^5 - k_7*x^7
    
    The bit-width of 18 appears often because it is the width of hardware
    multipliers on Altera FPGAs.
    
    Args:
        value: 20-bit unsigned fixed point integer upscaled by 2^20
        
    Returns:
        18-bit two's complement fixed point integer upscaled by 2^17
    """
    # These are polynomial constants generated for each term in the Taylor
    # series. They have been upscaled to the largest value that fits within
    # 18-bits for greatest precision. The constants labeled with [ADJ] have
    # been manually adjusted to increase accuracy.
    k1 = 205887  # k1 = round((2*PI)^1/1! * 2^15)
    k3 = 169336  # k3 = round((2*PI)^3/3! * 2^12)
    k5 = 167014  # k5 = round((2*PI)^5/5! * 2^11) [ADJ]
    k7 = 150000  # k7 = round((2*PI)^7/7! * 2^11) [ADJ]
    
    # Uses symmetric properties of sine to get more accurate results
    # Normalize the x value to a 18-bit value upscaled by 2^20
    high0 = ((value >> 19) & 0x01) != 0
    high1 = ((value >> 18) & 0x01) != 0
    x1 = value & 0x3ffff  # Strip two highest bits
    
    if high1:
        x1 = (((1 << 18) - x1) & 0x3ffff)
    
    negative = high0
    one = (x1 == 0) and high1
    
    # Compute the power values (most of these must be done in series)
    x2 = ((x1 * x1) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^22
    x3 = ((x2 * x1) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^24
    x5 = ((x2 * x3) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^28
    x7 = ((x2 * x5) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^32
    
    # Compute the polynomial values (these can be done in parallel)
    kx1 = ((k1 * x1) >> 17) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    kx3 = ((k3 * x3) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    kx5 = ((k5 * x5) >> 21) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    kx7 = ((k7 * x7) >> 25) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    
    # Add all the terms together (these can be done in series-parallel)
    sum_val = kx1 - kx3 + kx5 - kx7  # Scale: 2^18
    sum_val = sum_val >> 1  # Scale: 2^17
    
    # Perform reflection math and corrections
    if one:  # Check if sum should be one
        sum_val = (1 << 17)
    if negative:  # Check if the sum should be negative
        # Two's complement negation - use Python's negation
        # First mask to 18 bits to ensure we're working with the right range
        sum_val = sum_val & ((1 << 18) - 1)
        # If sign bit is set, interpret as negative
        if sum_val >= (1 << 17):
            sum_val = sum_val - (1 << 18)
        # Now negate
        sum_val = -sum_val
    
    return clamp_overflow(sum_val, 18)


def cosine(value: int) -> int:
    """
    Fixed-point cosine approximation. Normalized for an input domain of [0,1)
    instead of the usual domain of [0,2*PI).
    
    Uses Taylor series approximation for cosines centered at zero:
        cosine(2*PI*x) = 1 - (2*PI*x)^2/2! + (2*PI*x)^4/4!
                       - (2*PI*x)^6/6! + (2*PI*x)^8/8!
                     = 1 - k_2*x^2 + k_4*x^4 - k_6*x^6 + k_8*x^8
    
    The bit-width of 18 appears often because it is the width of hardware
    multipliers on Altera FPGAs.
    
    Args:
        value: 20-bit unsigned fixed point integer upscaled by 2^20
        
    Returns:
        18-bit two's complement fixed point integer upscaled by 2^17
    """
    # These are polynomial constants generated for each term in the Taylor
    # series. They have been upscaled to the largest value that fits within
    # 18-bits for greatest precision. The constants labeled with [ADJ] have
    # been manually adjusted to increase accuracy.
    k2 = 161704  # k2 = round((2*PI)^2/2! * 2^13)
    k4 = 132996  # k4 = round((2*PI)^4/4! * 2^11)
    k6 = 175016  # k6 = round((2*PI)^6/6! * 2^11)
    k8 = 241700  # k8 = round((2*PI)^8/8! * 2^12) [ADJ]
    
    # Uses symmetric properties of cosine to get more accurate results
    # Normalize the x value to a 18-bit value upscaled by 2^20
    high0 = ((value >> 19) & 0x01) != 0
    high1 = ((value >> 18) & 0x01) != 0
    x1 = value & 0x3ffff  # Strip two highest bits
    
    if high1:
        x1 = (((1 << 18) - x1) & 0x3ffff)
    
    negative = high0 ^ high1
    zero = (x1 == 0) and high1
    
    # Compute the power values (most of these must be done in series)
    x2 = ((x1 * x1) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^22
    x4 = ((x2 * x2) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^26
    x6 = ((x4 * x2) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^30
    x8 = ((x4 * x4) >> 18) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^34
    
    # Compute the polynomial values (these can be done in parallel)
    kx2 = ((k2 * x2) >> 17) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    kx4 = ((k4 * x4) >> 19) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    kx6 = ((k6 * x6) >> 23) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    kx8 = ((k8 * x8) >> 28) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    
    # Add all the terms together (these can be done in series-parallel)
    sum_val = ((1 << 18) - kx2 + kx4 - kx6 + kx8) & 0xFFFFFFFFFFFFFFFF  # Scale: 2^18
    sum_val = sum_val >> 1  # Scale: 2^17
    
    # Perform reflection math and corrections
    if zero:  # Check if sum should be zero
        sum_val = 0
    if negative:  # Check if the sum should be negative
        # Two's complement negation - use Python's negation
        # First mask to 18 bits to ensure we're working with the right range
        sum_val = sum_val & ((1 << 18) - 1)
        # If sign bit is set, interpret as negative
        if sum_val >= (1 << 17):
            sum_val = sum_val - (1 << 18)
        # Now negate
        sum_val = -sum_val
    
    return clamp_overflow(sum_val, 18)


# Convenience functions for geolocation calculations

def sin_radians(angle_radians: float) -> float:
    """Calculate sine of an angle in radians using fixed-point arithmetic.
    
    Args:
        angle_radians: Angle in radians
        
    Returns:
        Sine value as a float
    """
    # Handle NaN and Inf
    if math.isnan(angle_radians) or math.isinf(angle_radians):
        return math.nan
    
    # Normalize angle to [0, 2*PI)
    angle_radians = angle_radians % (2 * math.pi)
    if angle_radians < 0:
        angle_radians += 2 * math.pi
    
    # Convert to normalized [0, 1) domain
    normalized = angle_radians / (2 * math.pi)
    
    # Convert to fixed-point (20-bit scale)
    try:
        fixed_angle = float_to_fixed(normalized, 20)
    except (ValueError, OverflowError):
        # Fallback to standard math if fixed-point conversion fails
        return math.sin(angle_radians)
    
    # Calculate sine
    fixed_sin = sine(fixed_angle)
    
    # Convert back to float
    result = fixed_to_float(fixed_sin, 17)
    
    # Check for NaN in result
    if math.isnan(result):
        return math.sin(angle_radians)
    
    return result


def cos_radians(angle_radians: float) -> float:
    """Calculate cosine of an angle in radians using fixed-point arithmetic.
    
    Args:
        angle_radians: Angle in radians
        
    Returns:
        Cosine value as a float
    """
    # Handle NaN and Inf
    if math.isnan(angle_radians) or math.isinf(angle_radians):
        return math.nan
    
    # Normalize angle to [0, 2*PI)
    angle_radians = angle_radians % (2 * math.pi)
    if angle_radians < 0:
        angle_radians += 2 * math.pi
    
    # Convert to normalized [0, 1) domain
    normalized = angle_radians / (2 * math.pi)
    
    # Convert to fixed-point (20-bit scale)
    try:
        fixed_angle = float_to_fixed(normalized, 20)
    except (ValueError, OverflowError):
        # Fallback to standard math if fixed-point conversion fails
        return math.cos(angle_radians)
    
    # Calculate cosine
    fixed_cos = cosine(fixed_angle)
    
    # Convert back to float
    result = fixed_to_float(fixed_cos, 17)
    
    # Check for NaN in result
    if math.isnan(result):
        return math.cos(angle_radians)
    
    return result


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float, 
                       radius_km: float = 6371.0) -> float:
    """
    Calculate the great circle distance between two points on Earth using
    the Haversine formula with fixed-point trigonometric functions.
    
    Args:
        lat1: Latitude of first point in degrees
        lon1: Longitude of first point in degrees
        lat2: Latitude of second point in degrees
        lon2: Longitude of second point in degrees
        radius_km: Earth's radius in kilometers (default: 6371.0 km)
        
    Returns:
        Distance between the two points in kilometers
    """
    # Check for NaN or Inf in input coordinates
    if (math.isnan(lat1) or math.isnan(lon1) or math.isnan(lat2) or math.isnan(lon2) or
        math.isinf(lat1) or math.isinf(lon1) or math.isinf(lat2) or math.isinf(lon2)):
        return math.nan
    
    # Convert degrees to radians
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)
    
    # Calculate differences
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    
    # Haversine formula using fixed-point trig functions
    a = (sin_radians(dlat / 2) ** 2 + 
         cos_radians(lat1_rad) * cos_radians(lat2_rad) * 
         sin_radians(dlon / 2) ** 2)
    # Clamp a to [0, 1] to avoid domain errors in asin due to floating-point rounding
    # Fixed-point trig can produce values slightly outside [0, 1] due to approximation errors
    a = max(0.0, min(1.0, a))
    
    # Additional safety check - if a is still invalid, use standard math
    if not (0.0 <= a <= 1.0) or math.isnan(a) or math.isinf(a):
        # Fallback to standard haversine if fixed-point produces invalid value
        import math as math_std
        a_std = (math_std.sin(dlat / 2) ** 2 + 
                 math_std.cos(lat1_rad) * math_std.cos(lat2_rad) * 
                 math_std.sin(dlon / 2) ** 2)
        a = max(0.0, min(1.0, a_std))
    
    sqrt_a = math.sqrt(a)
    # Ensure sqrt_a is in valid range for asin
    sqrt_a = max(-1.0, min(1.0, sqrt_a))
    c = 2 * math.asin(sqrt_a)
    
    return radius_km * c


if __name__ == "__main__":
    # Demo: Print out 4096 samples of the approximate sine and cosine waves
    print("sine       cosine")
    for i in range(4096):
        angle = float_to_fixed(1.0 / 4096.0 * i, 20)
        sin_val = sine(angle)
        cos_val = cosine(angle)
        print(f"{fixed_to_float(sin_val, 17):+0.6f}, {fixed_to_float(cos_val, 17):+0.6f}")

