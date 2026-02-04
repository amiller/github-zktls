# Twitter Login Verification

## Problem
Need to verify the browser session belongs to the tweet author before capturing proof.

## Failed Approaches
- **DOM scraping for @mentions** - Unreliable, could match any @handle on page
- **Twitter API v1.1 endpoints** - Deprecated, return 404
- **GraphQL endpoints** - Require guessing query IDs, fragile
- **Python twitter-api-client** - API calls failing, library issues
- **twid cookie** - Contains user ID but not validated server-side

## Working Solution
Use Twitter's own `data-testid` attributes which are stable (used for their QA):

```javascript
const profileLink = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]')
const username = profileLink.getAttribute('href').slice(1)  // "/username" -> "username"
```

## Why data-testid is Reliable
- Twitter's QA team uses these for automated testing
- Changing them breaks their internal CI
- Consistent for 3+ years
- Semantic naming (describes element purpose)

## Flow
1. Inject cookies into browser
2. Navigate to `x.com/home` (triggers authenticated page load)
3. Extract username from profile link's href
4. Compare with tweet author from oEmbed

## Endpoints
- `POST /session` - Inject cookies
- `GET /twitter/me` - Returns `{"screen_name": "username"}`

## Cookie Extraction
```bash
python3 extract-cookies.py chrome x.com -o twitter-session.json
```
