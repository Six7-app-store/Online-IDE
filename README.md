# Online-IDE

Eine Java-Entwicklungsumgebung im Browser. Jedes Team bekommt eine eigene VM,
und jede Person darauf einen eigenen
[code-server](https://github.com/coder/code-server) (VS Code im Browser) mit
eigenem Port und eigenem Passwort.

## Vorinstallierte Software

- OpenJDK 21 (`java`, `javac`), kompiliert und startet direkt aus dem
  Terminal der IDE
- Python 3 (inkl. pip, venv), `build-essential`, Git

## Aufgaben

Jede Person findet nach dem Login `~/Coding-Aufgabe/` vor. Ohne Upload liegen
dort zehn Java-Übungen von „Hello World" bis zur binären Suche, aus
[`tofu/files/aufgaben/`](tofu/files/aufgaben/). Lädt der Dozent im Wizard
eine ZIP für ein Team hoch, ersetzt sie diese Übungen für alle
Teammitglieder.

Die ZIP reist im `user_data` der VM mit, und Nova nimmt davon höchstens 64 KB
an. Für die ZIP bleiben damit etwa **30 KB**. Ist sie größer, bricht der Plan
mit einer Meldung ab, bevor eine VM entsteht.

## User-Management

- **Ein Account pro Person**, abgeleitet aus der E-Mail-Adresse
  (`anna.alt@dhbw.de` → `annaalt`; beginnt der Name mit einer Ziffer, kommt
  ein `u` davor)
- Das Passwort gilt für die IDE, für `sudo` und für SSH
- Jede Person hat einen eigenen Port ab 8080, in der Reihenfolge der
  Mitglieder; die Zugangsdaten nennen ihn

## VM-Deployment

| | |
|---|---|
| VMs gesamt | **eine pro Team** (höchstens `max_teams`, Standard 15) |
| Personen je Team | höchstens 20 (Ports 8080–8099) |
| Größe | wählbar: `gp1.small`, `gp1.medium`, `gp1.large` (Standard `gp1.small`) |
| Festplatte | wählbar: 10–200 GB, Standard ist die Platte des Flavors (10 GB) |
| Erreichbar über | HTTP auf Port 8080 + n, wählbar über IPv6 (Standard), IPv4 oder beides |
| Floating IP | Nein |

Jeder code-server braucht einige hundert MB Arbeitsspeicher. Für Teams mit
mehr als drei, vier Personen besser `gp1.medium` oder größer wählen.

## Konfigurierbare Variablen

| Variable | Beschreibung | Standard |
|---|---|---|
| `assignment_files` | Aufgaben als ZIP pro Team, landen in `~/Coding-Aufgabe` | leer |
| `flavor` | Größe der Team-VM | `gp1.small` |
| `disk_size_gb` | Festplatte in GB, `0` nutzt die Platte des Flavors | `0` |
| `max_teams` | Obergrenze für Team-VMs in einem Deployment | `15` |
| `ip_mode` | Adressfamilie: `ipv4`, `ipv6` oder `dual` | `ipv6` |
| `network_uuid` | Netz mit öffentlicher IPv6, für `ipv6` und `dual` | `DHBWV6` |
| `network_v4_uuid` | Netz mit öffentlich gerouteter IPv4, für `ipv4` und `dual` | leer |
| `shared_secgroup_id` | ID der gemeinsamen Security Group | `default` |
| `web_source_v4` | IPv4-Präfix, das die IDEs erreichen darf | `141.72.0.0/16` |
| `web_source_v6` | IPv6-Präfix, das die IDEs erreichen darf | `::/0` |

## Erreichbarkeit

code-server lauscht nur auf `127.0.0.1`. Davor sitzt nginx und reicht jede
IDE auf ihrem öffentlichen Port weiter, für IPv4 und IPv6. Die Verbindung ist
unverschlüsseltes HTTP. Über IPv4 bleibt die IDE deshalb wie bisher auf
Campus und VPN beschränkt (`web_source_v4`). Für IPv6 ist das Campus-Präfix
nicht hinterlegt, und im Standardnetz wäre die VM sonst gar nicht erreichbar;
`web_source_v6` steht deshalb auf `::/0` und lässt sich im Wizard eingrenzen.

`ip_mode` funktioniert wie bei der
[Ubuntu-App](https://github.com/Six7-app-store/Ubuntu-App#adressfamilie-ip_mode).

## Einrichtung beim Boot

Es wird kein Image mehr gebaut (ADR 0010 im deployment-Repo). cloud-init legt
die Konten an und die Dateien aus [`tofu/files/`](tofu/files/) ab, danach
installiert [`online-ide-setup.sh`](tofu/files/online-ide-setup.sh) JDK,
code-server und nginx und startet eine IDE je Person.

Das Skript meldet erst Erfolg, wenn jede IDE über nginx antwortet. Scheitert
ein Schritt, scheitert `cloud-final.service`, und der App Store zeigt das
Deployment als fehlgeschlagen mit den passenden Zeilen aus der Konsole
(ADR 0011). Das Protokoll steht auf der VM in
`/var/log/cloud-init-output.log`.

Wie lange die Einrichtung auf newstack dauert, ist noch nicht gemessen.

## Prüfen ohne Cloud

```bash
cd tofu
tofu init -backend=false
tofu fmt -check -recursive
tofu validate
tofu test
```

Die Tests mocken alle Provider und brauchen keinen OpenStack-Zugang. Die CI
([`.github/workflows/opentofu.yml`](.github/workflows/opentofu.yml)) fährt
dieselben Schritte und prüft zusätzlich das Setup-Skript mit ShellCheck.
