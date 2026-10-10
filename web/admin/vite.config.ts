import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  // Regelmotoren ligger i web/golfgutu-core (utenfor denne mappa).
  server: { port: 5178, fs: { allow: [".."] } },
});
