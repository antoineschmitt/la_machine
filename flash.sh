#!/bin/sh
# The first time, or after modif sounds, flash all :
# ./flash.sh --sounds
# if only code change :
# ./flash.sh
# if calibration needed :
# ./flash.sh --calibrate             # code + reset calibration
# ./flash.sh --sounds --calibrate    # code + sounds + reset calibration

set -e
cd "$(dirname "$0")"

ESPTOOL="$HOME/Library/Arduino15/packages/esp32/tools/esptool_py/5.1.0/esptool"
AVM=_build/default/lib/la_machine.avm
SOUNDS=_build/generated/sounds.bin

# 1. Compilation + empaquetage avec les bibliothèques AtomVM
rebar3 atomvm packbeam -p -e atomvmlib.avm

SIZE=$(stat -f%z "$AVM")
if [ "$SIZE" -gt 1048576 ]; then
  echo "Erreur : $AVM fait $SIZE octets, plus que la partition boot.avm (1 Mo)"
  exit 1
fi

# 2. Ce qu'il faut flasher
#    Table de partitions réelle (image 1.4) :
#    nvs 0x9000 (0x6000) | boot.avm 0x130000 (0x100000)
#    resets 0x230000 (0x40000) | sounds 0x270000 (0xD90000)
FILES="0x130000 $AVM"
for arg in "$@"; do
  case "$arg" in
    --sounds)
      SOUNDS_SIZE=$(stat -f%z "$SOUNDS")
      if [ "$SOUNDS_SIZE" -gt 14221312 ]; then
        echo "Erreur : $SOUNDS fait $SOUNDS_SIZE octets, plus que la partition sounds"
        exit 1
      fi
      FILES="$FILES 0x270000 $SOUNDS"
      ;;
    --calibrate)
      NVS_BLANK=_build/nvs_blank.bin
      RESETS_BLANK=_build/resets_blank.bin
      head -c 24576 /dev/zero | LC_ALL=C tr '\0' '\377' > "$NVS_BLANK"
      head -c 262144 /dev/zero | LC_ALL=C tr '\0' '\377' > "$RESETS_BLANK"
      FILES="0x9000 $NVS_BLANK 0x230000 $RESETS_BLANK $FILES"
      ;;
    *)
      echo "Option inconnue : $arg (options : --sounds, --calibrate)"
      exit 1
      ;;
  esac
done

# 3. Attendre que la machine apparaisse
echo "Compilation OK. Appuyez sur le bouton de La Machine pour la réveiller..."
echo "Ctrl+C pour arrêter."
while true; do
  PORT=$(find /dev -name "cu.usbmodem*" | head -n 1)
  [ -n "$PORT" ] && break
  sleep 1
done
echo "Machine trouvée : $PORT"

# 4. Flash
"$ESPTOOL" --chip esp32c3 --port "$PORT" write-flash $FILES
