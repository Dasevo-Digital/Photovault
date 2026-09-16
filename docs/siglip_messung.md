# SigLIP 2 statt CLIP – gemessen und verworfen

Punkt 6 der 6. Vergleichsauflage. Der Vorschlag lautete: CLIP ViT-B/32 ist
von 2021, SigLIP 2 in derselben Grössenklasse schlägt es bei Bild-Text-Suche
und ist **mehrsprachig** – damit fiele die OPUS-MT-Übersetzung weg, die vor
jeder deutschen Suche hängt und die in der Stufe-2-Runde nur als „mässig
hilfreich" gemessen wurde.

Vor dem Bauen gemessen. Das Ergebnis trägt den Aufwand nicht.

## Der Aufbau

600 zufällige Fotos der echten Bibliothek, mit beiden Modellen eingebettet
(65 s für beide zusammen). Sechs Fragen, je die sechs besten Treffer:

- **CLIP** bekommt die Frage auf **Englisch** – also die bestmögliche
  Übersetzung, besser als OPUS-MT sie liefern würde. Bewusst zugunsten von
  CLIP: Wenn SigLIP dagegen nur gleichzieht, gibt es keinen Grund zu
  wechseln.
- **SigLIP 2** bekommt dieselbe Frage auf **Deutsch**.

Beurteilt wurden die Kontaktabzüge von Hand. Werkzeug:
`tool/siglip_vergleich/`.

## Das Ergebnis

| Frage | CLIP (englisch) | SigLIP 2 (deutsch) |
|---|---|---|
| ein Hund | 0 von 6 (immerhin Tiere) | 0 von 6 |
| Schnee im Winter | 5 | 6 |
| eine Geburtstagstorte | 5 | 3 |
| ein Boot auf dem Wasser | 5 | 5 |
| eine Kirche | 2 | 4 |
| Essen auf einem Teller | 6 | 5 |
| **zusammen** | **23 von 36** | **23 von 36** |

Ein Gleichstand. SigLIP versteht Deutsch tatsächlich unmittelbar – bei
„Schnee im Winter" fand es einen Menschen mit Schneeschieber, bei „eine
Kirche" ein Gewölbe und ein Wegkreuz. Es verliert die gewonnenen Punkte
aber bei „Geburtstagstorte" und „Essen" wieder.

## Was der Wechsel gekostet hätte

```
Modelldateien   CLIP    352 MB Bild + 254 MB Text  =   606 MB
                SigLIP  372 MB Bild + 1,13 GB Text =  1,50 GB
Zerleger        CLIP    BPE, 49.408 Stücke, liegt vor
                SigLIP  Gemma-BPE, 256.000 Stücke, tokenizer.json 34 MB,
                        in Dart neu zu schreiben und gegen die
                        Referenzbibliothek zu prüfen
Einbettungen    alle 7548 neu zu rechnen, 512 -> 768 Dimensionen,
                die gespeicherten sind unbrauchbar
Schwellen       ALLE neu zu eichen: SigLIPs Kosinuswerte liegen zwischen
                -0,03 und 0,09, CLIPs in einer ganz anderen Spanne. Die
                0,92 der Serienerkennung, die Duplikatschwelle und die
                Schwelle der KI-Schlagwörter träfen nichts mehr.
```

Der Text-Encoder ist deshalb so gross, weil die Einbettungstabelle für
256.000 Vokabeln allein rund 786 MB fp32 belegt. Genau diese Tabelle ist
das, was die Mehrsprachigkeit bezahlt.

## Was das nicht heisst

Nicht, dass SigLIP 2 schlechter wäre – die Rangliste sagt „gleich gut" bei
600 Fotos und sechs Fragen, und eine grössere Fassung (`so400m`) wäre
wahrscheinlich besser. Sie wäre auch 2,5-mal so gross.

Es heisst: Für **diese** Bibliothek und **diese** Fragen bringt der Tausch
nichts, was den Umbau trüge. Wenn ein kleineres mehrsprachiges Modell
auftaucht, ist die Messung in einer halben Stunde wiederholt.

## Nebenbefund

SigLIPs Ähnlichkeitswerte liegen in einer viel engeren Spanne als CLIPs.
Wer irgendwann tauscht, darf nicht nur die Einbettungen neu rechnen,
sondern muss jede Schwelle im Programm neu bestimmen – sonst findet die
Duplikatsuche alles oder nichts, und niemand merkt sofort, welches von
beidem.
