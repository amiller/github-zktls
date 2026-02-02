/**
 * Proof Generator Service Worker
 * Polls bridge for commands, injects cookies, captures screenshots
 */

const BRIDGE_URL = 'http://localhost:3000'
const KEEPALIVE_ALARM = 'proof-keepalive'

let currentUserAgent = null
let pollingActive = false

console.log('[Proof] Service worker starting...')

// Poll bridge for commands
async function pollOnce() {
  try {
    const res = await fetch(`${BRIDGE_URL}/api/commands`)
    if (res.ok) {
      const commands = await res.json()
      for (const cmd of commands) {
        console.log('[Proof] Command:', cmd.tool)
        await executeCommand(cmd)
      }
    }
  } catch (e) {
    // Bridge not ready, ignore
  }
}

async function startPolling() {
  if (pollingActive) return
  pollingActive = true
  console.log('[Proof] Starting bridge polling...')

  const deadline = Date.now() + 25000
  while (pollingActive && Date.now() < deadline) {
    await pollOnce()
    await new Promise(r => setTimeout(r, 100))
  }
  pollingActive = false
  setTimeout(() => startPolling(), 0)
}

// Keepalive alarm
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === KEEPALIVE_ALARM) startPolling()
})
chrome.alarms.create(KEEPALIVE_ALARM, { periodInMinutes: 0.4 })

// Execute command and send response
async function executeCommand(cmd) {
  let result = null, success = true, error = ''

  try {
    switch (cmd.tool) {
      case 'injectSession':
        result = await injectSession(cmd.args)
        break
      case 'navigate':
        result = await navigate(cmd.args)
        break
      case 'screenshot':
        result = await screenshot()
        break
      case 'captureProof':
        result = await captureProof()
        break
      default:
        throw new Error(`Unknown command: ${cmd.tool}`)
    }
  } catch (e) {
    success = false
    error = e.message
  }

  // Send response
  try {
    await fetch(`${BRIDGE_URL}/api/responses`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: cmd.id, success, result, error })
    })
  } catch (e) {
    console.error('[Proof] Failed to send response:', e)
  }
}

// Inject cookies and set user agent
async function injectSession({ cookies, userAgent }) {
  console.log('[Proof] Injecting session:', cookies?.length, 'cookies')

  // Inject cookies
  if (cookies?.length) {
    for (const cookie of cookies) {
      try {
        const url = `http${cookie.secure ? 's' : ''}://${cookie.domain.replace(/^\./, '')}${cookie.path || '/'}`
        await chrome.cookies.set({
          url,
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path || '/',
          secure: cookie.secure || false,
          httpOnly: cookie.httpOnly || false,
          sameSite: cookie.sameSite || 'lax',
          expirationDate: cookie.expirationDate || (Date.now() / 1000 + 86400)
        })
      } catch (e) {
        console.warn('[Proof] Failed to set cookie:', cookie.name, e.message)
      }
    }
  }

  // Set user agent via declarativeNetRequest
  if (userAgent) {
    currentUserAgent = userAgent
    await updateUserAgentRule(userAgent)
  }

  return { cookiesSet: cookies?.length || 0, userAgent: !!userAgent }
}

// Update UA spoofing rule
async function updateUserAgentRule(userAgent) {
  const ruleId = 1

  // Remove existing rule
  try {
    await chrome.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: [ruleId]
    })
  } catch (e) {}

  // Add new rule
  await chrome.declarativeNetRequest.updateDynamicRules({
    addRules: [{
      id: ruleId,
      priority: 1,
      action: {
        type: 'modifyHeaders',
        requestHeaders: [{
          header: 'User-Agent',
          operation: 'set',
          value: userAgent
        }]
      },
      condition: {
        urlFilter: '*',
        resourceTypes: ['main_frame', 'sub_frame', 'xmlhttprequest', 'script', 'image', 'stylesheet', 'font', 'other']
      }
    }]
  })
  console.log('[Proof] UA rule set:', userAgent.slice(0, 50))
}

// Navigate to URL
async function navigate({ url }) {
  console.log('[Proof] Navigating to:', url)
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true })

  if (tab) {
    await chrome.tabs.update(tab.id, { url })
  } else {
    await chrome.tabs.create({ url })
  }

  // Wait for load
  await new Promise(resolve => {
    const listener = (tabId, info) => {
      if (info.status === 'complete') {
        chrome.tabs.onUpdated.removeListener(listener)
        resolve()
      }
    }
    chrome.tabs.onUpdated.addListener(listener)
    setTimeout(resolve, 10000) // timeout
  })

  return { success: true, url }
}

// Take screenshot
async function screenshot() {
  const dataUrl = await chrome.tabs.captureVisibleTab({ format: 'png' })
  return { screenshot: dataUrl }
}

// Capture full proof
async function captureProof() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true })

  // Screenshot
  const dataUrl = await chrome.tabs.captureVisibleTab({ format: 'png' })

  // Get page info via content script
  let pageInfo = {}
  if (tab?.id) {
    try {
      const results = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => ({
          title: document.title,
          url: window.location.href,
          bodyText: document.body?.innerText?.slice(0, 1000)
        })
      })
      pageInfo = results[0]?.result || {}
    } catch (e) {
      console.warn('[Proof] Failed to get page info:', e)
    }
  }

  return {
    screenshot: dataUrl,
    url: tab?.url,
    title: tab?.title,
    pageInfo
  }
}

// Start polling immediately
startPolling()

console.log('[Proof] Service worker ready')
