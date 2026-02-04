#!/usr/bin/env python3
"""
Verify Twitter login by comparing user IDs.
- Extracts logged-in user ID from twid cookie
- Gets tweet author ID from tweet
- Compares them

Usage: ./verify-twitter-login.py <session_file> <tweet_url>
"""

import json
import sys
import re
from urllib.parse import unquote
from twitter.scraper import Scraper

def main():
    if len(sys.argv) < 3:
        print("Usage: verify-twitter-login.py <session_file> <tweet_url>", file=sys.stderr)
        sys.exit(1)

    session_file = sys.argv[1]
    tweet_url = sys.argv[2]

    # Extract tweet ID from URL
    match = re.search(r'/status/(\d+)', tweet_url)
    if not match:
        print(f"Invalid tweet URL: {tweet_url}", file=sys.stderr)
        sys.exit(1)
    tweet_id = int(match.group(1))

    # Load session
    with open(session_file) as f:
        session = json.load(f)

    cookies = {c['name']: c['value'] for c in session.get('cookies', [])}

    # Get logged-in user ID from twid cookie
    twid = unquote(cookies.get('twid', ''))
    if not twid.startswith('u='):
        print("twid cookie not found or invalid format", file=sys.stderr)
        sys.exit(1)

    logged_in_user_id = int(twid.replace('u=', ''))
    print(f"Logged-in user ID: {logged_in_user_id}", file=sys.stderr)

    # Create scraper
    scraper = Scraper(cookies={"ct0": cookies['ct0'], "auth_token": cookies['auth_token']})

    # Get tweet to find author
    try:
        tweets = scraper.tweets_by_ids([tweet_id])
        if not tweets:
            print("Could not fetch tweet", file=sys.stderr)
            sys.exit(1)

        tweet = tweets[0]
        # Navigate nested structure: data.tweetResult[0].result.core.user_results.result
        result = tweet['data']['tweetResult'][0]['result']
        user_result = result['core']['user_results']['result']
        author_id = int(user_result['rest_id'])
        author_handle = user_result['legacy']['screen_name']

        print(f"Tweet author: @{author_handle} (ID: {author_id})", file=sys.stderr)

        if logged_in_user_id == author_id:
            print(f"MATCH: Logged in as tweet author @{author_handle}", file=sys.stderr)
            print(author_handle)  # Output username on success
            sys.exit(0)
        else:
            print(f"MISMATCH: Logged in as {logged_in_user_id}, tweet by {author_id}", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"Error fetching tweet: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
