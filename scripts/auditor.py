import math
import sys
from collections import Counter

def calculate_entropy(data):
    """
    Calculates the Shannon Entropy of the given data.
    Target for cryptographic security: > 7.5 bits/byte.
    """
    if not data:
        return 0
    entropy = 0
    length = len(data)
    counts = Counter(data)
    for count in counts.values():
        probability = count / length
        entropy -= probability * math.log2(probability)
    return entropy

def main():
    if len(sys.argv) < 2:
        print("--- JAVS IDMC Auditor ---")
        print("Usage: python auditor.py <file_path or string>")
        return
    
    input_val = sys.argv[1]
    
    # Try to treat as file path first
    try:
        with open(input_val, 'rb') as f:
            data = f.read()
    except Exception:
        # If not a file, treat as raw string
        data = input_val.encode()

    entropy = calculate_entropy(data)
    print(f"[*] Analyzing Data of size: {len(data)} bytes")
    print(f"[*] Shannon Entropy: {entropy:.4f} bits/byte")
    
    if entropy > 7.5:
        print("[+] Status: AUDIT PASSED (High Randomness detected)")
        print("[+] Data is resistant to standard frequency analysis.")
    else:
        print("[-] Status: AUDIT FAILED")
        print("[-] Target entropy > 7.5 not met. Key rotation recommended (REACT MTD).")

if __name__ == "__main__":
    main()
