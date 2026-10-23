// Verdiene fra env/<miljø>/.env (se env.ts).
interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_KEY?: string;
  readonly VITE_TURNSTILE_SITE_KEY?: string;
}
