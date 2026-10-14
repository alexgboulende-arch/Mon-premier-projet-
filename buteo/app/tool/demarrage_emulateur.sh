#!/usr/bin/env bash
# Installe l'APK sur l'émulateur, ouvre Buteo et vérifie que l'app tourne
# toujours 40 secondes plus tard. Garde une capture d'écran et le journal.
# Usage : demarrage_emulateur.sh <apk> <dossier de sortie>
set -u
APK=$1
SORTIE=$2
PAQUET=com.buteo.pronostics
mkdir -p "$SORTIE"

adb install -r "$APK" || exit 1
adb logcat -c
adb shell am start -W -n "$PAQUET/com.buteo.buteo.MainActivity"
sleep 40

adb exec-out screencap -p > "$SORTIE/ecran.png"
adb logcat -d -v time > "$SORTIE/journal.txt"

echo "----- Erreurs du journal -----"
grep -E "FATAL EXCEPTION|AndroidRuntime|flutter|DartVM|Exception|$PAQUET" "$SORTIE/journal.txt" | head -150

if adb shell pidof "$PAQUET" > /dev/null; then
  echo "Buteo tourne toujours après 40 secondes."
else
  echo "::error::Buteo s'est arrêtée au démarrage (voir le journal ci-dessus)."
  exit 1
fi
