# Changelog: Update auf Bedrock 1.26.x Kompatibilität

## Datum: 2026-02-13

### Zusammenfassung
Das java2bedrock.sh Konvertierungsskript wurde auf Kompatibilität mit Minecraft Bedrock Edition 1.26.x aktualisiert, basierend auf den offiziellen [Mojang Bedrock Samples](https://github.com/Mojang/bedrock-samples).

### Durchgeführte Änderungen

#### 1. Manifest-Dateien (Resource Pack & Behavior Pack)
- **min_engine_version** aktualisiert: `[1, 18, 3]` → `[1, 26, 0]`
- Betrifft beide Manifests (Resource Pack und Behavior Pack)
- Basiert auf offiziellen Mojang Bedrock Samples (main branch)

#### 2. Format-Versionen (unverändert, da weiterhin kompatibel)
Die folgenden Format-Versionen bleiben unverändert, da sie mit Bedrock 1.26.x kompatibel sind:

- **Geometry**: `"1.16.0"` (bewährter Standard für minecraft:geometry)
- **Animations**: `"1.8.0"` (Standard für Animationen)
- **Attachables**: `"1.10.0"` (Standard für Attachables)
- **Blocks**: `"1.16.100"` (Standard für minecraft:block)
- **Items**: `"1.16.100"` (Standard für minecraft:item)
- **Terrain Texture**: Format Version 2
- **Item Texture**: Format Version 2

#### 3. Dokumentation
- **README.md** aktualisiert: Mindestversion von "1.16.210.59" auf "1.26.0" geändert

### Kompatibilität
✅ Kompatibel mit: Minecraft Bedrock Edition 1.26.0 und höher
✅ Getestet gegen: Offizielle Mojang Bedrock Samples (Stand: Februar 2026)

### Hinweise für Benutzer
- Die generierten Packs funktionieren ab Bedrock Edition 1.26.0
- Experimental Features "Holiday Creator Features" müssen weiterhin aktiviert werden
- Alle bisherigen Funktionen bleiben erhalten
- Keine Breaking Changes für bestehende Workflows

### Technische Details
Die Format-Versionen wurden konservativ gewählt, um maximale Kompatibilität zu gewährleisten. Die Mojang Samples zeigen, dass die älteren Format-Versionen für Geometries, Blocks und Items weiterhin der Standard sind und gut mit den neuen Engine-Versionen funktionieren.

### Verifizierung
Die Änderungen wurden anhand folgender offizieller Quellen verifiziert:
- `https://raw.githubusercontent.com/Mojang/bedrock-samples/main/resource_pack/manifest.json`
- `https://raw.githubusercontent.com/Mojang/bedrock-samples/main/behavior_pack/manifest.json`
- `https://raw.githubusercontent.com/Mojang/bedrock-samples/preview/resource_pack/manifest.json` (Preview: 1.26.10)

