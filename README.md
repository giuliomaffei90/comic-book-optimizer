# Comic Book Optimizer

App macOS nativa (SwiftUI) per preparare fumetti alla lettura su iPad con Panels.

Trascini un `.cbr`, `.cbz`, `.zip`, `.rar`, `.7z` o una cartella di immagini; l'app:

1. estrae le pagine e le ordina naturalmente;
2. classifica ogni pagina rispetto alla mediana del volume stesso:
   - **pagina normale** (~1×): passa;
   - **tavola doppia** (~2×): se le due metà sono già presenti come pagine singole adiacenti
     (confronto con difference hash) la scarta da sola, altrimenti te la mostra con la linea
     di taglio già piazzata a metà;
   - **fuori formato** (tutto il resto: foldout a tre o più ante, scansioni storte, banner):
     te la mostra senza tagli preimpostati.

   In entrambi i casi il processo si ferma sull'editor: puoi tenere la pagina, eliminarla,
   ritagliarla, spostare o aggiungere linee di taglio verticali, sfogliare le pagine vicine
   con le frecce e zoomare fino a 8× per lavorare al pixel. Con la lettura manga i pezzi
   vengono riordinati destra → sinistra;
3. riduce le pagine che superano 2048×2732 (risoluzione nativa dell'iPad Pro 12.9");
4. ricodifica in JPEG qualità 81% e, se vuoi, fa un passaggio con **ImageOptim** (usa le sue preferenze);
5. riscrive tutto in un `.cbz` accanto all'originale e chiede se conservare i file di partenza.

## Dipendenze

Nessuna. `libarchive` (zip/rar/rar5/7z in lettura, zip in scrittura) è già in macOS,
la grafica passa per ImageIO/CoreGraphics. ImageOptim è opzionale: se non è installata,
la spunta non compare.

## Build

```sh
./bundle.sh          # → "Comic Book Optimizer.app"
swift run ComicOptimizer --selftest   # verifica split / dedup / ordine manga
```
