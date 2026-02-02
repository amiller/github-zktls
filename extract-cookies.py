#!/usr/bin/env python3
"""
Extract cookies from Chrome/Chromium browsers.
Based on yt-dlp's cookie extraction (refs/yt-dlp/yt_dlp/cookies.py)

Usage:
    ./extract-cookies.py chrome twitter.com
    ./extract-cookies.py chrome twitter.com --output cookies.json
"""

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

def get_chrome_cookie_path():
    """Get Chrome cookie database path for current platform."""
    if sys.platform == 'darwin':
        return Path.home() / 'Library/Application Support/Google/Chrome/Default/Cookies'
    elif sys.platform == 'win32':
        return Path(os.environ['LOCALAPPDATA']) / 'Google/Chrome/User Data/Default/Network/Cookies'
    else:  # Linux
        return Path.home() / '.config/google-chrome/Default/Cookies'

def get_chromium_cookie_path():
    """Get Chromium cookie database path for current platform."""
    if sys.platform == 'darwin':
        return Path.home() / 'Library/Application Support/Chromium/Default/Cookies'
    elif sys.platform == 'win32':
        return Path(os.environ['LOCALAPPDATA']) / 'Chromium/User Data/Default/Network/Cookies'
    else:
        return Path.home() / '.config/chromium/Default/Cookies'

BROWSER_PATHS = {
    'chrome': get_chrome_cookie_path,
    'chromium': get_chromium_cookie_path,
}

def pbkdf2_sha1(password, salt, iterations, key_length):
    return hashlib.pbkdf2_hmac('sha1', password, salt, iterations, key_length)

def decrypt_v10_linux(encrypted_value):
    """Decrypt v10 cookies on Linux (AES-CBC with 'peanuts' key)."""
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.backends import default_backend
    except ImportError:
        print("Warning: cryptography not installed, can't decrypt v10 cookies", file=sys.stderr)
        print("Install with: pip install cryptography", file=sys.stderr)
        return None

    key = pbkdf2_sha1(b'peanuts', b'saltysalt', 1, 16)
    iv = b' ' * 16

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    decrypted = decryptor.update(encrypted_value) + decryptor.finalize()

    # Remove PKCS7 padding
    padding_len = decrypted[-1]
    return decrypted[:-padding_len].decode('utf-8')

def extract_cookies(browser, domain_filter=None):
    """Extract cookies from browser's SQLite database."""
    path_fn = BROWSER_PATHS.get(browser)
    if not path_fn:
        raise ValueError(f"Unsupported browser: {browser}. Supported: {list(BROWSER_PATHS.keys())}")

    cookie_path = path_fn()
    if not cookie_path.exists():
        raise FileNotFoundError(f"Cookie database not found: {cookie_path}")

    # Copy database to temp file (browser may have it locked)
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir) / 'Cookies'
        shutil.copy2(cookie_path, tmp_path)

        conn = sqlite3.connect(tmp_path)
        conn.text_factory = bytes
        cursor = conn.cursor()

        # Query cookies
        if domain_filter:
            # Match domain and subdomains
            cursor.execute(
                'SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure '
                'FROM cookies WHERE host_key LIKE ? OR host_key LIKE ?',
                (f'%{domain_filter}', f'.{domain_filter}')
            )
        else:
            cursor.execute(
                'SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure '
                'FROM cookies'
            )

        cookies = []
        for row in cursor.fetchall():
            host_key, name, value, encrypted_value, path, expires_utc, is_secure = row

            host_key = host_key.decode() if isinstance(host_key, bytes) else host_key
            name = name.decode() if isinstance(name, bytes) else name
            path = path.decode() if isinstance(path, bytes) else path

            # Handle value vs encrypted_value
            if value:
                value = value.decode() if isinstance(value, bytes) else value
            elif encrypted_value:
                # Check encryption version
                if encrypted_value[:3] == b'v10':
                    value = decrypt_v10_linux(encrypted_value[3:])
                elif encrypted_value[:3] == b'v11':
                    # v11 requires keyring access - skip for now
                    print(f"Warning: v11 encrypted cookie '{name}' for {host_key} - skipping (needs keyring)", file=sys.stderr)
                    continue
                else:
                    print(f"Warning: Unknown encryption for cookie '{name}' - skipping", file=sys.stderr)
                    continue

            if value is None:
                continue

            cookies.append({
                'name': name,
                'value': value,
                'domain': host_key,
                'path': path,
                'secure': bool(is_secure),
                'httpOnly': True,  # Assume httpOnly since we're reading from DB
                'expirationDate': expires_utc / 1000000 - 11644473600 if expires_utc else None,  # Chrome timestamp to Unix
            })

        conn.close()
        return cookies

def get_user_agent():
    """Get Chrome's user agent string."""
    # Default to a recent Chrome UA
    if sys.platform == 'darwin':
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    elif sys.platform == 'win32':
        return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    else:
        return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def main():
    parser = argparse.ArgumentParser(description='Extract cookies from browser')
    parser.add_argument('browser', choices=list(BROWSER_PATHS.keys()), help='Browser to extract from')
    parser.add_argument('domain', nargs='?', help='Domain to filter cookies (e.g., twitter.com)')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')
    parser.add_argument('--include-ua', action='store_true', help='Include user agent in output')
    args = parser.parse_args()

    try:
        cookies = extract_cookies(args.browser, args.domain)

        output = {'cookies': cookies}
        if args.include_ua:
            output['userAgent'] = get_user_agent()

        json_output = json.dumps(output, indent=2)

        if args.output:
            with open(args.output, 'w') as f:
                f.write(json_output)
            print(f"Extracted {len(cookies)} cookies to {args.output}", file=sys.stderr)
        else:
            print(json_output)

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error extracting cookies: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
