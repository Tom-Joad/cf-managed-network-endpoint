# cf-managed-network-endpoint

TLS-Endpunkt für **Cloudflare Zero Trust "Managed Networks"**.

Der Container liefert auf Port **6443** ein selbstsigniertes TLS-Zertifikat aus.
Der Cloudflare-WARP-Client (Cloudflare One Client) verbindet sich dorthin und
vergleicht den SHA-256-Fingerprint des Zertifikats, um zu erkennen, ob sich das
Gerät im Heimnetz befindet. Der Container hat **keine Anwendungslogik** — er ist
eine reine Identitäts-Bake; die HTTP-Antwort (`200`, plain text) ist irrelevant,
es zählt nur der TLS-Handshake.

## ⚠️ Fingerprint-Stabilität (wichtigster Punkt)

Die Netzwerkerkennung bricht **stillschweigend**, sobald sich der Fingerprint
ändert. Deshalb:

- Das Zertifikat wird **nicht** ins Image gebacken und **nicht** bei jedem
  Start neu erzeugt.
- Beim Start prüft das Entrypoint-Script, ob unter `/certs/` bereits
  `cert.pem` und `key.pem` liegen. Wenn ja → verwenden. Wenn nein → **einmalig**
  erzeugen (RSA 2048, 3650 Tage, `CN=managed-network.internal`) und dort
  ablegen.
- `/certs` muss ein **persistentes Volume** sein. Solange es erhalten bleibt,
  überlebt der Fingerprint Container-Neustarts, Image-Rebuilds und Updates.
- **Das Volume niemals löschen.** Sonst entsteht beim nächsten Start ein neues
  Zertifikat mit neuem Fingerprint, und der neue Wert muss in Cloudflare
  nachgetragen werden. Am besten den Appdata-Ordner ins Backup aufnehmen.
- Liegt im Volume nur *eine* der beiden Dateien, bricht der Container mit
  Fehler ab, statt still ein neues Zertifikat zu erzeugen.

## Fingerprint auslesen

**1. Container-Log (einfachster Weg):** Bei *jedem* Start schreibt der
Container den Fingerprint gut sichtbar ins Log — in der Unraid-Oberfläche:
Container-Icon → *Logs*.

```
==================================================================
 SHA-256-Fingerprint des TLS-Zertifikats

   AB:CD:...

 Fuer Cloudflare Zero Trust (Managed Networks, ohne Doppelpunkte):

   abcd...
==================================================================
```

**2. Manuell im laufenden Container:**

```sh
docker exec cf-managed-network-endpoint \
  openssl x509 -in /certs/cert.pem -noout -fingerprint -sha256
```

**3. Remote über das Netz:**

```sh
openssl s_client -connect <STATISCHE-IP>:6443 </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256
```

Cloudflare erwartet den Wert **ohne Doppelpunkte** (das Log gibt beide
Formate aus).

## Image beziehen (privates ghcr.io-Package)

Das Package ist privat. Auf der Unraid-Maschine einmalig anmelden — mit einem
GitHub-PAT (classic) mit Scope `read:packages`:

```sh
docker login ghcr.io -u Tom-Joad
# Passwort: der PAT
```

Unraid speichert die Anmeldung in `/root/.docker/config.json`; danach
funktionieren Pull und Auto-Update über die Unraid-UI.

## Deployment auf Unraid

Zielumgebung (Werte an dein eigenes Netzwerk anpassen):

| Parameter          | Wert                                        |
| ------------------ | ------------------------------------------- |
| Netzwerk           | eigenes VLAN, Subnetz `<SUBNETZ>` (z. B. `10.0.0.0/24`) |
| Statische IP       | `<STATISCHE-IP>` (außerhalb des DHCP-Pools) |
| Gateway            | `<GATEWAY>`                                 |
| Docker-Netzwerk    | Custom-VLAN-Interface `br0.<VLAN-ID>` (nicht bridge) |
| Port               | `6443` (TLS)                                |
| Volume             | `/mnt/user/appdata/cf-managed-network-endpoint/certs` → `/certs` |

Beim Custom-VLAN-Interface lauscht der Container direkt unter seiner eigenen
IP — ein Port-Mapping ist nicht nötig.

**Variante A — Unraid-Template:** [unraid/cf-managed-network-endpoint.xml](unraid/cf-managed-network-endpoint.xml)
nach `/boot/config/plugins/dockerMan/templates-user/` kopieren, dann in der
Unraid-UI *Add Container* → Template auswählen und die feste IP unter
"Fixed IP address" setzen.

**Variante B — docker run:**

```sh
docker run -d \
  --name cf-managed-network-endpoint \
  --network br0.<VLAN-ID> \
  --ip <STATISCHE-IP> \
  -v /mnt/user/appdata/cf-managed-network-endpoint/certs:/certs \
  --restart unless-stopped \
  ghcr.io/tom-joad/cf-managed-network-endpoint:latest
```

## Cloudflare Zero Trust konfigurieren

1. Fingerprint aus dem Container-Log kopieren (Format ohne Doppelpunkte).
2. Zero-Trust-Dashboard → **Settings → WARP Client → Network locations →
   Managed networks → Add new managed network**.
3. Typ *TLS*, Host `<STATISCHE-IP>`, Port `6443`, SHA-256-Fingerprint eintragen.
4. In den WARP-**Device-Profilen** das Managed Network als Bedingung verwenden
   (z. B. eigenes Profil, wenn Netzwerk = Heimnetz erkannt).

Der WARP-Client prüft die Erreichbarkeit bei jedem Netzwerkwechsel. Erwartetes
Verhalten testen: Gerät ins Heimnetz bringen → im WARP-Client wechselt das
Geräteprofil.

## Entwicklung

```sh
docker build -t cf-managed-network-endpoint .
docker run -d --name cfmne-test -p 6443:6443 -v cfmne-certs:/certs cf-managed-network-endpoint
curl -k https://localhost:6443/          # -> 200 "cf-managed-network-endpoint"
docker logs cfmne-test                   # Fingerprint
```

CI ([.github/workflows/build-and-push.yml](.github/workflows/build-and-push.yml))
baut bei jedem Push auf `main` sowie bei Tags `v*` ein Multi-Arch-Image
(`linux/amd64`, `linux/arm64`) und pusht es nach
`ghcr.io/tom-joad/cf-managed-network-endpoint` (Tags: `latest`, `sha-…`,
Semver bei Tags).
