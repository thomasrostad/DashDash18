import { useEffect, useState } from "react";
import { SHARE_TEXT, TV_TEXT, displayURL, spacedCode, tavlaMessage, tavlaURL, tvURL } from "./sharing.ts";
import { tavlaShareCode, tavlaShareCurrent, tavlaShareRevoke, tvCode, tvCodeRevoke } from "./sharingApi.ts";
import { QRCode } from "./QRCode.tsx";
import { errorText } from "./supabase.ts";
import type { Competition } from "./data.ts";

/** TV-kode og «Del tavla» for arrangøren, som TVCodeSheet og TavlaShareSheet i appen. */
export function ScreenShare({ competition }: { competition: Competition }) {
  return (
    <div className="grid2">
      <TVCodeCard competition={competition} />
      <TavlaShareCard competition={competition} />
    </div>
  );
}

function useAction() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  async function run(action: () => Promise<void>, done?: string) {
    setBusy(true); setError(null); setNotice(null);
    try { await action(); if (done) setNotice(done); }
    catch (e) { setError(errorText(e)); }
    finally { setBusy(false); }
  }
  return { busy, error, notice, run };
}

/** Kopierer lenken (web-utgaven av «Del lenken»). */
function CopyLink({ url, text, busy }: { url: string; text?: string; busy: boolean }) {
  const [copied, setCopied] = useState(false);
  return (
    <button type="button" className="primary" disabled={busy} onClick={async () => {
      await navigator.clipboard.writeText(text ? `${text} ${url}` : url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }}>{copied ? "Kopiert" : "Kopier lenken"}</button>
  );
}

function TVCodeCard({ competition }: { competition: Competition }) {
  const [code, setCode] = useState<string | null>(null);
  const [shown, setShown] = useState(false);
  const { busy, error, notice, run } = useAction();

  return (
    <div className="card">
      <h3>TV-kode</h3>
      <p className="muted">{TV_TEXT.footer(competition.name)}</p>
      {code ? (
        <div>
          <QRCode value={tvURL(code)} label="QR-kode til TV-visningen" />
          <p className="big-code">{spacedCode(code)}</p>
          <p className="muted">{TV_TEXT.howTo}</p>
          <p><a href={tvURL(code)} target="_blank" rel="noreferrer">{displayURL(tvURL(code))}</a></p>
        </div>
      ) : shown && !busy ? <p className="muted">{TV_TEXT.none}</p> : null}
      <div className="inline">
        {code && <CopyLink url={tvURL(code)} busy={busy} />}
        {!shown ? (
          <button type="button" className="primary" disabled={busy}
            onClick={() => run(async () => { setCode(await tvCode(competition.id)); setShown(true); })}>Vis TV-koden</button>
        ) : (
          <button type="button" className="tab" disabled={busy}
            onClick={() => run(async () => { setCode(await tvCode(competition.id, code !== null)); }, code ? "Ny kode laget. Den gamle virker ikke lenger." : undefined)}>
            {code ? "Ny kode" : "Lag kode"}
          </button>
        )}
        {code && (
          <button type="button" className="link" disabled={busy}
            onClick={() => confirm(TV_TEXT.revokeQuestion) && run(async () => { await tvCodeRevoke(competition.id); setCode(null); }, "Koden er trukket tilbake.")}>
            Trekk tilbake
          </button>
        )}
      </div>
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
    </div>
  );
}

function TavlaShareCard({ competition }: { competition: Competition }) {
  const [code, setCode] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);
  const { busy, error, notice, run } = useAction();

  useEffect(() => {
    let live = true;
    setLoaded(false);
    run(async () => { const c = await tavlaShareCurrent(competition.id); if (live) setCode(c); })
      .then(() => { if (live) setLoaded(true); });
    return () => { live = false; };
  }, [competition.id]);

  const url = code ? tavlaURL(code) : null;
  return (
    <div className="card">
      <h3>Del tavla</h3>
      <label className="check">
        <input type="checkbox" checked={code !== null} disabled={busy || !loaded}
          onChange={(e) => {
            const on = e.target.checked;
            run(async () => {
              if (on) setCode(await tavlaShareCode(competition.id));
              else { await tavlaShareRevoke(competition.id); setCode(null); }
            }, on ? "Tavla deles nå med en lenke." : "Delingen er slått av. Lenken virker ikke lenger.");
          }} />
        {SHARE_TEXT.toggle}
      </label>
      <p className="muted">{SHARE_TEXT.toggleFooter}</p>
      {url ? (
        <>
          <p><a href={url} target="_blank" rel="noreferrer"><code>{displayURL(url)}</code></a></p>
          <p className="muted">{SHARE_TEXT.on}</p>
          <div className="inline">
            <CopyLink url={url} text={tavlaMessage(competition.name)} busy={busy} />
            <button type="button" className="tab" disabled={busy}
              onClick={() => confirm(SHARE_TEXT.renewQuestion) && run(async () => setCode(await tavlaShareCode(competition.id, true)), "Ny lenke laget. Den gamle virker ikke lenger.")}>
              Ny lenke
            </button>
          </div>
          <p className="muted">{SHARE_TEXT.onFooter}</p>
        </>
      ) : loaded ? <p className="muted">{SHARE_TEXT.off}</p> : null}
      {error && <p className="error">{error}</p>}
      {notice && <p className="ok">{notice}</p>}
    </div>
  );
}
