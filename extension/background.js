// Background service worker for GitHub zkTLS extension
// Currently minimal - will handle GitHub Actions triggers in the future

chrome.runtime.onInstalled.addListener(() => {
  console.log('🦞 GitHub zkTLS extension installed');
});

// Future: Listen for messages from popup to trigger GitHub Actions
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'TRIGGER_GITHUB_ACTION') {
    // TODO: Implement GitHub Actions trigger
    console.log('GitHub Action trigger requested:', message);
    sendResponse({ success: false, error: 'Not implemented yet' });
  }
});
