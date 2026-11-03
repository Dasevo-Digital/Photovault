'use strict';

// --- Passkeys (#277) -----------------------------------------------------------
//
// Der Browser spricht mit dem Gerät (navigator.credentials), der Server
// prüft (konten/passkeys.dart). Dazwischen nur das Umpacken: Der Server
// schickt Byteketten als base64url, der Browser will ArrayBuffer – und
// umgekehrt.
//
// Diese Datei dient zweimal: der Weboberfläche (Anmelden, Einstellungen)
// und der Seite passkey.html, über die das Telefon im Browser anmeldet oder
// einen Passkey anlegt (siehe passkey_api.dart).

const passkeyB64 = {
  aus(puffer) {
    const b = new Uint8Array(puffer);
    let s = '';
    for (const x of b) s += String.fromCharCode(x);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  },
  zu(text) {
    const s = atob(text.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((text.length + 3) % 4));
    const b = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
    return b;
  },
};

function passkeysMoeglich() {
  return !!(window.PublicKeyCredential && navigator.credentials && window.isSecureContext);
}

async function passkeyAnlegen(optionen) {
  const o = {
    ...optionen,
    challenge: passkeyB64.zu(optionen.challenge),
    user: { ...optionen.user, id: passkeyB64.zu(optionen.user.id) },
    excludeCredentials: (optionen.excludeCredentials || []).map((c) => ({ ...c, id: passkeyB64.zu(c.id) })),
  };
  const k = await navigator.credentials.create({ publicKey: o });
  return {
    id: k.id,
    rawId: passkeyB64.aus(k.rawId),
    type: k.type,
    response: {
      clientDataJSON: passkeyB64.aus(k.response.clientDataJSON),
      attestationObject: passkeyB64.aus(k.response.attestationObject),
    },
  };
}

async function passkeyBestaetigen(optionen) {
  const o = { ...optionen, challenge: passkeyB64.zu(optionen.challenge) };
  const k = await navigator.credentials.get({ publicKey: o });
  return {
    id: k.id,
    rawId: passkeyB64.aus(k.rawId),
    type: k.type,
    response: {
      clientDataJSON: passkeyB64.aus(k.response.clientDataJSON),
      authenticatorData: passkeyB64.aus(k.response.authenticatorData),
      signature: passkeyB64.aus(k.response.signature),
      userHandle: k.response.userHandle ? passkeyB64.aus(k.response.userHandle) : null,
    },
  };
}

// Ein abgebrochener Dialog ist kein Fehler, den man lesen muss.
function passkeyAbgebrochen(x) {
  return x && (x.name === 'NotAllowedError' || x.name === 'AbortError');
}

async function passkeyPost(pfad, json) {
  const r = await fetch(pfad, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', 'X-PV-Web': '1' },
    body: JSON.stringify(json || {}),
  });
  let d = null;
  try { d = await r.json(); } catch (_) { /* keine Daten */ }
  if (!r.ok) {
    const f = new Error(d && d.fehler ? t(d.fehler) : t('Fehler {n}', { n: r.status }));
    f.status = r.status;
    throw f;
  }
  return d;
}

// --- Die Seite für das Telefon ---------------------------------------------------

if (document.body && document.body.dataset.seite === 'passkey') {
  const q = new URLSearchParams(location.search);
  const ticket = q.get('ticket');
  const meldung = (text) => { document.getElementById('meldung').textContent = text; };
  const knopf = document.getElementById('los');
  document.getElementById('titel').textContent = ticket ? t('Passkey für Photo Vault anlegen') : t('Mit Passkey anmelden');
  knopf.textContent = ticket ? t('Passkey anlegen') : t('Weiter mit Passkey');
  document.getElementById('name-feld').hidden = !ticket;
  if (!passkeysMoeglich()) {
    knopf.disabled = true;
    meldung(t('Dieser Browser kann keine Passkeys.'));
  }
  knopf.addEventListener('click', async () => {
    knopf.disabled = true;
    meldung('');
    try {
      if (ticket) {
        const o = await passkeyPost('/api/v1/passkeys/ticket/optionen', { ticket });
        const antwort = await passkeyAnlegen(o.optionen);
        await passkeyPost('/api/v1/passkeys/ticket', { ticket, antwort, name: document.getElementById('name').value.trim() });
        meldung(t('Der Passkey ist angelegt. Zurück zur App – dieses Fenster lässt sich schliessen.'));
        return;
      }
      const o = await passkeyPost('/api/v1/anmelden/passkey/optionen');
      const antwort = await passkeyBestaetigen(o.optionen);
      const d = await passkeyPost('/api/v1/anmelden/passkey', {
        antwort,
        pruefwert: q.get('pruefwert'),
        rueckweg: q.get('rueckweg'),
        zustand: q.get('zustand'),
        geraet: q.get('geraet'),
      });
      location.href = d.weiter;
    } catch (x) {
      knopf.disabled = false;
      meldung(passkeyAbgebrochen(x) ? t('Abgebrochen.') : x.message);
    }
  });
}
