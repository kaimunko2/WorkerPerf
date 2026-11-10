# Drittanbieter-Inhalte

## Superpowers (`.claude/skills/`)

Die Skills unter `.claude/skills/` stammen aus dem Projekt
[obra/superpowers](https://github.com/obra/superpowers) von Jesse Vincent und stehen unter der
MIT-Lizenz (siehe unten). Sie sind eine Arbeitshilfe für Claude Code in diesem Repository und
kein Bestandteil von WorkerPerf selbst.

- Übernommene Version: 7.0.2, Commit `22f0b463e7a5e579904dd6211a520321035526f7` (03.11.2026)
- Übernommen wurde nur das Verzeichnis `skills/`. Der SessionStart-Hook des Plugins, der den
  Skill `using-superpowers` automatisch in jede Sitzung lädt, ist nicht enthalten.
- Einzige Änderung: Verweise zwischen den Skills in der Plugin-Schreibweise
  `superpowers:<skill>` wurden auf `<skill>` gekürzt, weil die Skills hier als Projekt-Skills
  ohne Plugin-Präfix geladen werden.

Aktualisieren: `skills/` aus dem Upstream-Repository erneut nach `.claude/skills/` kopieren und
das Präfix `superpowers:` vor den Skill-Namen wieder entfernen. Wer stattdessen das Plugin
„Superpowers“ im eigenen Claude-Konto aktiviert, sollte `.claude/skills/` löschen, damit die
Skills nicht doppelt erscheinen.

### Lizenz

```text
MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
