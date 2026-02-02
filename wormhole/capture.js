#!/usr/bin/env node
// Capture script - uses puppeteer with SOCKS5 proxy
import puppeteer from 'puppeteer'

async function main() {
  const profile = process.argv[2] || 'socrates1024'
  const cookies = JSON.parse(process.env.SESSION_JSON || '{"cookies":[]}')

  console.log('🌐 Launching browser with SOCKS5 proxy...')
  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--proxy-server=socks5://127.0.0.1:1080',
      '--no-sandbox',
      '--disable-setuid-sandbox'
    ]
  })

  const page = await browser.newPage()

  // Set cookies
  if (cookies.cookies?.length) {
    const xCookies = cookies.cookies
      .filter(c => c.domain?.includes('x.com') || c.domain?.includes('twitter.com'))
      .map(c => ({
        name: c.name,
        value: c.value,
        domain: c.domain.startsWith('.') ? c.domain : '.' + c.domain,
        path: c.path || '/',
        secure: c.secure ?? true,
        httpOnly: c.httpOnly ?? true
      }))
    await page.setCookie(...xCookies)
    console.log(`   Set ${xCookies.length} cookies`)
  }

  // Set user agent
  if (cookies.userAgent) {
    await page.setUserAgent(cookies.userAgent)
  }

  console.log(`📸 Navigating to https://x.com/${profile}...`)
  await page.goto(`https://x.com/${profile}`, { waitUntil: 'networkidle2', timeout: 30000 })
  await page.waitForTimeout(3000)

  await page.screenshot({ path: '../proof/screenshot.png', fullPage: false })
  console.log('   Screenshot saved!')

  await browser.close()
}

main().catch(e => { console.error(e); process.exit(1) })
