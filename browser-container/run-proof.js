// Playwright script: Run zkTLS proof with injected cookies
// This runs inside GitHub Actions or locally for testing

import { chromium } from 'playwright';
import { writeFileSync, mkdirSync } from 'fs';
import path from 'path';

const TARGET_URL = process.env.TARGET_URL || 'http://host.docker.internal:3000/profile';
const COOKIES_JSON = process.env.COOKIES || '[]';
const OUTPUT_DIR = process.env.OUTPUT_DIR || './proof-output';

async function runProof() {
  console.log('🦞 GitHub zkTLS Proof Generator');
  console.log('================================\n');
  
  // Parse cookies
  let cookies;
  try {
    cookies = JSON.parse(COOKIES_JSON);
    console.log(`✓ Loaded ${cookies.length} cookie(s)`);
  } catch (e) {
    console.error('✗ Failed to parse cookies:', e.message);
    process.exit(1);
  }
  
  // Create output directory
  mkdirSync(OUTPUT_DIR, { recursive: true });
  
  // Launch browser
  console.log('\nLaunching Chromium...');
  const browser = await chromium.launch({
    headless: true,
    args: ['--disable-dev-shm-usage']
  });
  
  const context = await browser.newContext({
    // Add cookies to context
    cookies: cookies.map(cookie => ({
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain || 'localhost',
      path: cookie.path || '/',
      httpOnly: cookie.httpOnly || false,
      secure: cookie.secure || false,
      sameSite: cookie.sameSite || 'Lax'
    }))
  });
  
  console.log('✓ Cookies injected into browser context');
  
  const page = await context.newPage();
  
  // Enable request/response logging
  const networkLog = [];
  page.on('request', request => {
    networkLog.push({
      type: 'request',
      timestamp: new Date().toISOString(),
      method: request.method(),
      url: request.url(),
      headers: request.headers()
    });
  });
  
  page.on('response', response => {
    networkLog.push({
      type: 'response',
      timestamp: new Date().toISOString(),
      status: response.status(),
      url: response.url(),
      headers: response.headers()
    });
  });
  
  console.log(`\nNavigating to: ${TARGET_URL}`);
  
  try {
    // Visit target page
    await page.goto(TARGET_URL, { waitUntil: 'networkidle' });
    console.log('✓ Page loaded');
    
    // Take screenshot
    const screenshotPath = path.join(OUTPUT_DIR, 'proof-screenshot.png');
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.log(`✓ Screenshot saved: ${screenshotPath}`);
    
    // Extract page content
    const pageContent = await page.content();
    const pageTitle = await page.title();
    const pageUrl = page.url();
    
    // Check if authenticated (look for common indicators)
    const bodyText = await page.textContent('body');
    const isAuthenticated = bodyText.includes('Logged in') || 
                          bodyText.includes('Profile') ||
                          bodyText.includes('@');
    
    console.log(`✓ Page title: ${pageTitle}`);
    console.log(`✓ Final URL: ${pageUrl}`);
    console.log(`✓ Authentication detected: ${isAuthenticated}`);
    
    // If there's an API endpoint, try fetching it
    let apiData = null;
    if (TARGET_URL.includes('/profile')) {
      const apiUrl = TARGET_URL.replace('/profile', '/api/data');
      console.log(`\nFetching API data from: ${apiUrl}`);
      
      try {
        const apiResponse = await page.goto(apiUrl);
        if (apiResponse.ok()) {
          apiData = await apiResponse.json();
          console.log('✓ API data retrieved:', JSON.stringify(apiData, null, 2));
        }
      } catch (e) {
        console.log('⚠ Could not fetch API data:', e.message);
      }
    }
    
    // Generate proof certificate
    const proof = {
      generated: new Date().toISOString(),
      target: {
        url: TARGET_URL,
        finalUrl: pageUrl,
        title: pageTitle
      },
      authentication: {
        authenticated: isAuthenticated,
        method: 'cookie-based',
        cookieCount: cookies.length
      },
      evidence: {
        screenshot: 'proof-screenshot.png',
        pageContentLength: pageContent.length,
        bodyTextPreview: bodyText.substring(0, 200),
        networkRequests: networkLog.length
      },
      apiData: apiData,
      environment: {
        userAgent: await page.evaluate(() => navigator.userAgent),
        timestamp: new Date().toISOString(),
        platform: process.platform
      }
    };
    
    // Save proof certificate
    const proofPath = path.join(OUTPUT_DIR, 'proof-certificate.json');
    writeFileSync(proofPath, JSON.stringify(proof, null, 2));
    console.log(`\n✓ Proof certificate saved: ${proofPath}`);
    
    // Save network log
    const networkPath = path.join(OUTPUT_DIR, 'network-log.json');
    writeFileSync(networkPath, JSON.stringify(networkLog, null, 2));
    console.log(`✓ Network log saved: ${networkPath}`);
    
    // Save page HTML
    const htmlPath = path.join(OUTPUT_DIR, 'page-content.html');
    writeFileSync(htmlPath, pageContent);
    console.log(`✓ Page HTML saved: ${htmlPath}`);
    
    console.log('\n================================');
    console.log('🎉 Proof generation complete!');
    console.log(`\nOutput directory: ${OUTPUT_DIR}`);
    console.log(`Authenticated: ${isAuthenticated}`);
    if (apiData) {
      console.log(`User: @${apiData.user?.username || 'unknown'}`);
    }
    
  } catch (error) {
    console.error('\n✗ Proof generation failed:', error.message);
    
    // Save error screenshot
    try {
      await page.screenshot({ path: path.join(OUTPUT_DIR, 'error-screenshot.png') });
    } catch (e) {
      // Ignore screenshot errors
    }
    
    throw error;
  } finally {
    await browser.close();
  }
}

// Run proof generation
runProof().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
