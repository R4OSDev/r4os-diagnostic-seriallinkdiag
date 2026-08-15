R4SLD.R4X
=========

R4SLD.R4X ist die Serial-Link-Service-Diagnose.

Projektstruktur seit 0.51.21:
- `build.zig` baut die Diagnose als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad, R4L-Imports und Contract.

Build:

    cd Code\System\Diagnostics\SerialLinkDiag
    ..\..\..\DevTools\Zig\zig.exe build

Ergebnis:

    Code\System\Diagnostics\SerialLinkDiag\zig-out\R4SLD.R4X

Contract:
- Build-Profil: `Zig/R4XStart`
- R4XStart-Entry: `r4sld_main`
- App-Klasse: `console`
- R4L-Imports: `R4SYS`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\TERMINAL\DIAG\R4SLD.R4X`
