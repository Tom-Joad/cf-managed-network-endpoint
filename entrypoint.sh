#!/bin/sh
set -eu

CERT_DIR=/certs
CERT="$CERT_DIR/cert.pem"
KEY="$CERT_DIR/key.pem"
CN="managed-network.internal"

if [ -f "$CERT" ] && [ -f "$KEY" ]; then
    echo "Vorhandenes Zertifikat wird verwendet: $CERT"
elif [ -f "$CERT" ] || [ -f "$KEY" ]; then
    # Nur eine der beiden Dateien vorhanden: NICHT still neu erzeugen,
    # sonst wechselt der Fingerprint und die Netzwerkerkennung bricht.
    echo "FEHLER: $CERT_DIR enthaelt nur eine der Dateien cert.pem/key.pem." >&2
    echo "Volume pruefen bzw. aus Backup wiederherstellen - es wird bewusst" >&2
    echo "KEIN neues Zertifikat erzeugt, um den Fingerprint nicht zu aendern." >&2
    exit 1
else
    echo "Kein Zertifikat gefunden - erzeuge einmalig ein neues (CN=$CN, RSA 2048, 3650 Tage)"
    mkdir -p "$CERT_DIR"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -subj "/CN=$CN" \
        -keyout "$KEY" -out "$CERT"
    chmod 600 "$KEY"
fi

FP_COLON=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2)
FP_PLAIN=$(printf '%s' "$FP_COLON" | tr -d ':' | tr 'A-F' 'a-f')

echo "=================================================================="
echo " SHA-256-Fingerprint des TLS-Zertifikats"
echo ""
echo "   $FP_COLON"
echo ""
echo " Fuer Cloudflare Zero Trust (Managed Networks, ohne Doppelpunkte):"
echo ""
echo "   $FP_PLAIN"
echo "=================================================================="

exec nginx -g "daemon off;"
