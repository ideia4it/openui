import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const backend = "http://localhost:4000";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: { "/chat": backend, "/tools": backend, "/library.json": backend },
  },
});
