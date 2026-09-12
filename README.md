# Comic Book Optimizer

App macOS nativa (SwiftUI) per preparare fumetti alla lettura su iPad con Panels.

Trascini un `.cbr`, `.cbz`, `.zip`, `.rar`, `.7z` o una cartella di immagini; l'app:

1. estrae le pagine e le ordina naturalmente;
2. classifica ogni pagina rispetto alla mediana del volume stesso:
   - **pagina normale** (~1×): passa;
   - **tavola doppia** (~2×): se le due metà sono già presenti come pagine singole adiacenti
     (confronto con difference hash) scarta la doppia, altrimenti la divide nell'ordine giusto
     per il senso di lettura scelto (manga = destra → sinistra);
   - **fuori formato** (tutto il resto: foldout a tre o più ante, scansioni storte, banner):
     il processo si ferma e ti mostra l'immagine. Puoi tenerla, eliminarla, oppure ritagliarla e
     tagliarla lungo quante linee verticali servono;
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
