# Fuzzy Fingerprint Server

A server implementation for browser fingerprint identification.

## Prerequisites

- Node.js (v14 or higher)
- npm (v6 or higher)

## Installation

1. Clone the repository
2. Navigate to the project directory:
   ```bash
   cd fingerprint_logic
   ```
3. Install dependencies:
   ```bash
   npm install
   ```

## Running the Server

### Development Mode
To run the server in development mode with auto-reload:
```bash
npm run dev
```

### Production Mode
To run the server in production mode:
```bash
npm start
```

The server will start on http://localhost:8080 by default. You can change the port by setting the `PORT` environment variable.

## Scripts

- `npm run dev`: Start the server in development mode with auto-reload
- `npm start`: Start the server in production mode
- `npm run build`: Build the TypeScript files (if any)
- `npm run test:fuzzy`: Run a fuzzy hashing test on several test fingerprints

## Environment Variables

- `PORT`: Server port (default: 8080) 