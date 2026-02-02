// Test webservice for github-zktls development
// Simple cookie-based authentication to simulate Twitter/etc

import express from 'express';
import cookieParser from 'cookie-parser';
import { randomUUID } from 'crypto';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;

// In-memory session store (for testing)
const sessions = new Map();
const users = new Map([
  ['alice', { password: 'password123', profile: { username: 'alice', bio: 'Test user Alice', verified: true } }],
  ['bob', { password: 'password456', profile: { username: 'bob', bio: 'Test user Bob', verified: false } }]
]);

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());
app.use(express.static('public'));

// Middleware: check if authenticated
function requireAuth(req, res, next) {
  const sessionId = req.cookies.sessionId;
  if (!sessionId || !sessions.has(sessionId)) {
    return res.status(401).json({ error: 'Not authenticated' });
  }
  req.user = sessions.get(sessionId);
  next();
}

// Homepage
app.get('/', (req, res) => {
  const sessionId = req.cookies.sessionId;
  const isLoggedIn = sessionId && sessions.has(sessionId);
  
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>GitHub zkTLS Test Service</title>
      <style>
        body { font-family: system-ui; max-width: 600px; margin: 50px auto; padding: 20px; }
        .success { color: green; }
        .error { color: red; }
        input, button { padding: 8px; margin: 5px 0; }
        button { background: #0066ff; color: white; border: none; cursor: pointer; }
      </style>
    </head>
    <body>
      <h1>GitHub zkTLS Test Service</h1>
      ${isLoggedIn ? `
        <p class="success">✓ Logged in as <strong>${sessions.get(sessionId).username}</strong></p>
        <p><a href="/profile">View Profile</a></p>
        <p><a href="/api/data">API Data (JSON)</a></p>
        <form action="/logout" method="POST">
          <button type="submit">Logout</button>
        </form>
      ` : `
        <h2>Login</h2>
        <form action="/login" method="POST">
          <div><input type="text" name="username" placeholder="Username (alice or bob)" required /></div>
          <div><input type="password" name="password" placeholder="Password (password123)" required /></div>
          <button type="submit">Login</button>
        </form>
        <p><small>Test accounts: alice/password123 or bob/password456</small></p>
      `}
      
      <hr>
      <h3>For Extension Testing:</h3>
      <p>Current cookies:</p>
      <pre id="cookies"></pre>
      <script>
        document.getElementById('cookies').textContent = document.cookie || '(none)';
      </script>
    </body>
    </html>
  `);
});

// Login endpoint
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  
  if (!users.has(username)) {
    return res.status(401).send('Invalid username or password');
  }
  
  const user = users.get(username);
  if (user.password !== password) {
    return res.status(401).send('Invalid username or password');
  }
  
  // Create session
  const sessionId = randomUUID();
  sessions.set(sessionId, { username, ...user.profile });
  
  res.cookie('sessionId', sessionId, {
    httpOnly: false, // Allow JavaScript access (for extension testing)
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    sameSite: 'lax'
  });
  
  console.log(`✓ User ${username} logged in (session: ${sessionId})`);
  res.redirect('/');
});

// Logout endpoint
app.post('/logout', (req, res) => {
  const sessionId = req.cookies.sessionId;
  if (sessionId) {
    sessions.delete(sessionId);
  }
  res.clearCookie('sessionId');
  res.redirect('/');
});

// Profile page (requires auth)
app.get('/profile', requireAuth, (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Profile - ${req.user.username}</title>
      <style>
        body { font-family: system-ui; max-width: 600px; margin: 50px auto; padding: 20px; }
        .badge { display: inline-block; padding: 3px 8px; background: #0066ff; color: white; border-radius: 3px; font-size: 12px; }
      </style>
    </head>
    <body>
      <h1>Profile: @${req.user.username}</h1>
      ${req.user.verified ? '<span class="badge">✓ Verified</span>' : ''}
      <p><strong>Bio:</strong> ${req.user.bio}</p>
      <p><strong>Session ID:</strong> <code>${req.cookies.sessionId}</code></p>
      <hr>
      <p><a href="/">← Back to home</a></p>
      
      <h3>zkTLS Proof Target</h3>
      <p>This page proves ownership of @${req.user.username} account.</p>
      <p>A Playwright script can screenshot this page to generate a verifiable proof.</p>
    </body>
    </html>
  `);
});

// API endpoint (returns JSON - easier for Playwright to verify)
app.get('/api/data', requireAuth, (req, res) => {
  res.json({
    authenticated: true,
    user: {
      username: req.user.username,
      bio: req.user.bio,
      verified: req.user.verified
    },
    timestamp: new Date().toISOString(),
    sessionId: req.cookies.sessionId
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'github-zktls-test-service',
    timestamp: new Date().toISOString(),
    activeSessions: sessions.size
  });
});

app.listen(PORT, () => {
  console.log(`🦞 GitHub zkTLS Test Service`);
  console.log(`📍 http://localhost:${PORT}`);
  console.log(`\nTest accounts:`);
  console.log(`  - alice / password123`);
  console.log(`  - bob / password456`);
  console.log(`\nReady for cookie extraction testing!`);
});
