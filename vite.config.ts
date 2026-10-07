import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import basicSsl from '@vitejs/plugin-basic-ssl';

// DEV: https://localhost:7443 (self-signed cert)
export default defineConfig(({ command }) => ({
  plugins: [react(), ...(command === 'serve' ? [basicSsl()] : [])],
  server: { host: true, port: 7443, strictPort: true },
  preview: { host: true, port: 7443, strictPort: true },
  test: { environment: 'node', include: ['src/**/*.test.ts'] },
}));
