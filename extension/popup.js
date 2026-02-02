// Cookie extraction UI logic

let extractedCookies = null;

document.getElementById('extractBtn').addEventListener('click', async () => {
  const domain = document.getElementById('domain').value.trim();
  const statusEl = document.getElementById('status');
  const cookieListEl = document.getElementById('cookieList');
  const copyBtn = document.getElementById('copyBtn');
  
  if (!domain) {
    // Get current tab domain
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const url = new URL(tab.url);
    document.getElementById('domain').value = url.hostname;
    return;
  }
  
  statusEl.className = 'status info';
  statusEl.textContent = `Extracting cookies for ${domain}...`;
  
  try {
    // Get all cookies for the domain
    const cookies = await chrome.cookies.getAll({ domain });
    
    if (cookies.length === 0) {
      statusEl.className = 'status error';
      statusEl.textContent = `No cookies found for ${domain}`;
      return;
    }
    
    extractedCookies = cookies.map(cookie => ({
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path,
      httpOnly: cookie.httpOnly,
      secure: cookie.secure,
      sameSite: cookie.sameSite
    }));
    
    // Display cookies
    cookieListEl.innerHTML = extractedCookies.map(c => 
      `<div class="cookie-item"><strong>${c.name}</strong>: ${c.value.substring(0, 30)}${c.value.length > 30 ? '...' : ''}</div>`
    ).join('');
    cookieListEl.style.display = 'block';
    
    statusEl.className = 'status success';
    statusEl.textContent = `✓ Extracted ${cookies.length} cookie(s)`;
    
    copyBtn.style.display = 'block';
    
  } catch (error) {
    statusEl.className = 'status error';
    statusEl.textContent = `Error: ${error.message}`;
    console.error('Cookie extraction error:', error);
  }
});

document.getElementById('copyBtn').addEventListener('click', async () => {
  if (!extractedCookies) return;
  
  const statusEl = document.getElementById('status');
  const cookiesJson = JSON.stringify(extractedCookies, null, 2);
  
  try {
    await navigator.clipboard.writeText(cookiesJson);
    statusEl.className = 'status success';
    statusEl.textContent = '✓ Cookies copied to clipboard! Paste into GitHub Actions.';
    
    // Also save to storage for later
    await chrome.storage.local.set({ lastExtractedCookies: extractedCookies });
    
  } catch (error) {
    statusEl.className = 'status error';
    statusEl.textContent = `Copy failed: ${error.message}`;
  }
});

// Auto-fill current domain on load
chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
  if (tab && tab.url) {
    try {
      const url = new URL(tab.url);
      document.getElementById('domain').value = url.hostname;
    } catch (e) {
      // Ignore invalid URLs
    }
  }
});
