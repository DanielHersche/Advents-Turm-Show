# Turm-Show Adventskerzen – info-beamer-Paket

Stand: 26.09.2026 · Entwurf, noch nicht auf dem Gerät getestet

## Was das Paket macht

- **Kalender:** 1.–24.12.2026. Satz K1 ab Di 1.12., K2 ab So 6.12., K3 ab So 13.12. und K4 ab So 20.12. bis Do 24.12.
- **Zeitfenster pro Tag:** morgens 06:00–08:00, abends 16:45–22:00
- **Ablauf pro Zeitfenster:** Intro einmal, danach läuft der Loop nahtlos bis zum Fensterende, dann das Outro einmal, danach schwarz
- **Beamer:** wird vor Showbeginn aus dem Standby geholt und nach dem Outro wieder in den Standby geschickt, per HDMI-CEC und/oder PJLink über LAN
- **Vier-Ecken-Korrektur:** aus dem Paket «Eckenkorrektur» übernommen, mit Messraster und Prüfraster

| Zeitpunkt (Beispiel Abend) | Was passiert |
|---|---|
| 16:44:00 | Beamer einschalten (Vorlauf 60 s). Das Bild ist noch schwarz. |
| 16:45:00 | Intro startet, danach der Loop |
| 22:00:00 | Outro startet |
| 22:02:00 | Beamer geht in den Standby (Nachlauf 120 s) |

## Dateien

| Datei | Zweck |
|---|---|
| `package.json` | Paketangaben, Plattformen pi-4 und pi-5 |
| `node.json` | Einstellungsmaske im Dashboard: Kalender, Filme, Beamer, Geometrie |
| `node.lua` | Wiedergabe: Intro → Loop → Outro, Überblendung, Eckenkorrektur |
| `service` | **ohne Endung!** Python-Dienst mit Kalender und Beamersteuerung (CEC/PJLink) |
| `messraster.png`, `pruefraster.png` | Raster zum Einmessen |
| `empty.png`, `package.png` | Platzhalter und Paketsymbol |

Aufgabenteilung: Nur der Dienst kennt Datum und Uhrzeit. Er meldet dem Node jede 2 Sekunden eine Zahl: 0 heisst keine Show, 1–4 heisst Show mit K1–K4. `node.lua` kümmert sich nur um die Wiedergabe.

## Einstellungen im Setup

**Betrieb**
- *Betriebsart:* Automatik (Kalender), Dauerbetrieb (Test, der gewählte Satz läuft sofort) oder Beamer immer im Standby
- *Anzeige:* Betrieb oder die Einmess-Modi 1–3. In den Einmess-Modi ist der Beamer immer an.

**Kalender:** Datum als `2026-12-01` oder `1.12.2026`, Zeit als `16:45` oder `21:59:30`. Die Endzeit ist der Zeitpunkt, an dem das Outro beginnt. Soll das Outro um 22:00 **fertig** sein, die Endzeit um die Outro-Länge früher setzen, zum Beispiel `21:59:40` bei 20 s Outro.

**Filme:** Pro Satz Intro, Loop und Outro. Pflicht ist nur der Loop. Fehlt das Intro, wird der Loop eingeblendet. Fehlt das Outro, wird er ausgeblendet. Format wie bisher HEVC.

**Übergänge**
- *Länge Loop-Film = 0:* Bei Fensterende blendet das Outro sofort über den Loop (Standard 1 s).
- *Länge Loop-Film = 20* (exakte Länge in Sekunden): Der Loop läuft bis zum Ende seines aktuellen Durchgangs weiter. Dann wird hart ins Outro geschnitten. Das passt, wenn das Outro mit dem letzten Loop-Bild beginnt. Das Outro startet dann bis zu 20 s später, deshalb den Nachlauf entsprechend lang wählen. Ob die Berechnung über fünf Stunden bildgenau bleibt, muss man am Gerät prüfen. Falls nicht, auf 0 zurückstellen.

**Beamer ein/aus**
- *Vorlauf / Nachlauf* in Sekunden. Der Nachlauf muss länger sein als das Outro, bei Loop-Länge > 0 zusätzlich plus eine Loop-Länge.
- *HDMI-CEC:* Der Dienst sendet `tv on` / `tv off`.
- *PJLink:* IP-Adresse und Passwort des Beamers. Der Dienst fragt alle 30 s den Zustand ab und korrigiert ihn bei Bedarf. So wird ein verpasster Befehl, etwa nach einem Stromunterbruch, nachgeholt.
- Beides gleichzeitig ist möglich und empfohlen, weil es doppelt absichert.

## Einstellungen am Panasonic PT-VMZ62 (aus dem Handbuch)

- **[PROJEKTOR EINST.] → [ECO MANAGEMENT] → [BEREITSCHAFTS MODUS] = [NORMAL]**
  - Nur so bleibt das Netzwerk im Standby aktiv und PJLink kann den Beamer wecken.
  - Bei [ECO] ist das Netzwerk aus, und der Beamer braucht ausserdem länger bis zum Bild.
- **HDMI-CEC** unter [PROJEKTOR EINST.] → [HDMI CEC]:
  - [HDMI CEC] = [EIN]
  - [GERÄT → PROJEKTOR] = [EIN-/AUSSCHALTEN]. Damit schaltet der Pi den Beamer ein und aus.
  - [PROJEKTOR → GERÄT] = [INAKTIV], damit der Beamer den Pi nicht mitschaltet.
- **PJLink** (unterstützt Klasse 1 und 2):
  - Zuerst muss ein Administrator-Passwort gesetzt sein, sonst ist die ganze Netzwerkfunktion gesperrt.
  - Dann unter [NETZWERK] → [PJLink] die [PJLink STEUERUNG] auf [EIN] stellen und ein [PJLink-PASSWORT] setzen. Dieses Passwort kommt ins Setup.
  - Der Beamer braucht eine **feste IP-Adresse**, entweder statisch oder als DHCP-Reservierung im Router.
  - Der Beamer muss per LAN im selben Netz wie der Pi hängen, im Gehäuse also über einen kleinen Switch.

## Paket anlegen

1. Neues GitHub-Repository anlegen, zum Beispiel `Turm-Show`, öffentlich. Alle Dateien hochladen. `service` **ohne** Endung hochladen und keine Kopien wie `_2` mithochladen.
2. In info-beamer: Packages → Add package → Create from url, dann die Repository-URL eingeben. Falls die Meldung «master does not exist» erscheint, die ZIP-URL `…/archive/refs/heads/main.zip` verwenden.
3. Aus dem Paket ein Setup anlegen, die zwölf Filme zuweisen und das Setup dem Gerät zuweisen.
4. Prüfen: Unter «Nodes in this package» muss bei *Service* ein Eintrag stehen.

Der bisherige «Kerzen Loop Player» bleibt unverändert und kann parallel weiterlaufen, zum Beispiel am Samsung-Testbildschirm.

## Testen im Herbst

1. **Ablauf:** Betriebsart *Automatik*. Das Datum «K1 ab» auf heute setzen, «Letzter Showtag» ebenfalls auf heute und ein Zeitfenster auf die nächsten 5 Minuten. Beobachten: Einschalten nach dem Vorlauf, Intro, Loop, Outro zur Endzeit, Standby nach dem Nachlauf.
2. **Wochenwechsel:** Für K2 das Datum morgen setzen und am nächsten Tag das Morgenfenster beobachten. Oder schneller: Satz K2 im *Dauerbetrieb* testen.
3. **Standby:** Einmal nur mit CEC testen (PJLink-IP leer), einmal nur mit PJLink (CEC aus). So weiss man, welcher Weg allein funktioniert.
4. **Protokoll:** Im Dashboard unter dem Gerät erscheinen Zeilen `[turm-show] …`, zum Beispiel `2026-12-01 16:45:00 -> Show K1 | Beamer an`.
5. Am Schluss die Kalenderwerte wieder auf Dezember stellen: 2026-12-01 / 06 / 13 / 20, Ende 2026-12-24.

## Offene Punkte / zu prüfen am Gerät

- [ ] `paused = true` und `:start()` beim Vorladen des Loops. Sonst gibt es beim Übergang vom Intro zum Loop eine kleine Lücke.
- [ ] Wie verhält sich `tv off` am Beamer: Geht er in den Standby oder wird nur das Bild schwarz?
- [ ] PJLink-Verbindung vom Pi zum Beamer (IP-Adresse, Passwort, Bereitschaftsmodus NORMAL)
- [ ] Systemzeit nach einem Neustart ohne Internet: Ohne NTP bleibt der Beamer aus, bis die Zeit stimmt.
- [ ] Zwei Pi (West- und Ostseite): Beide Setups brauchen dieselben Kalenderwerte. Die Filme und die Eckenwerte sind je Seite eigene.
