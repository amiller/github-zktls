/**
 * Proof Generator Content Script
 * Runs on all pages, provides page info to service worker
 */

console.log('[Proof] Content script loaded:', window.location.href)

// Listen for messages from service worker
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'getPageInfo') {
    sendResponse({
      url: window.location.href,
      title: document.title,
      bodyText: document.body?.innerText?.slice(0, 2000),
      html: document.documentElement?.outerHTML?.slice(0, 50000)
    })
  }
  return true
})
