FROM mcr.microsoft.com/playwright:v1.40.0-jammy

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy Playwright scripts
COPY *.js ./

# Copy browser extension (will be loaded by Playwright)
COPY extension /app/extension

# Expose Chrome DevTools port (for debugging)
EXPOSE 9222

CMD ["node", "run-proof.js"]
