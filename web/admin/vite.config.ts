import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { readConfig } from "./src/env.ts";

export default defineConfig(({ command, mode }) => {
  // Hvert miljø har sin egen mappe (env/test, env/prod), så verdier fra test aldri lekker inn i prod.
  const envDir = `env/${mode}`;
  if (command === "build") {
    const read = readConfig(mode, loadEnv(mode, envDir, "VITE_"));
    if ("error" in read) throw new Error(read.error);
  }
  return {
    plugins: [react()],
    envDir,
    // Regelmotoren ligger i web/golfgutu-core (utenfor denne mappa).
    server: { port: 5178, fs: { allow: [".."] } },
  };
});
