# Proxmox mit Ansible automatisieren

*Von Martin Gerhard Loschwitz*

Das Automatisierungstool Ansible hilft beim Aufsetzen und Betreiben von Proxmox-Clustern. Eine spezielle Ansible-Rolle installiert und konfiguriert Hosts reproduzierbar. Ansible kann sogar Ceph-Storage unter Proxmox einbinden.

## Einführung

Administratoren setzen zunehmend auf Automatisierungswerkzeuge, um wiederkehrende Aufgaben zuverlässig, reproduzierbar und frei von der Fehlerquelle Mensch auszuführen. Bei der Virtualisierungsplattform Proxmox VE (Virtual Environment) stehen Installationen, das Bootstrapping neuer Cluster, Storage-Einstellungen und Anpassungen an der Netzwerkkonfiguration in vielen Umgebungen regelmäßig an und Admins profitieren dabei erheblich von Automatisierung.

Das Automationstool Ansible bietet dabei mehrere Vorteile: Es arbeitet agentenlos, greift per SSH auf Zielsysteme zu und erzeugt eine Infrastruktur, die sich ohne zusätzliche Komponenten verwalten lässt. Unternehmen steigen daher mit Ansible ohne allzu große Hürden in das Thema Automatisierung ein. Der Artikel zeigt, wie man eine virtualisierte Infrastruktur mit Proxmox VE und Ansible in kurzer Zeit aufbaut.

Eine Ansible-Umgebung entsteht mit wenigen Befehlen auf einer Debian- oder Ubuntu-Workstation und erhält sofort lauffähige Playbooks, Module und umfangreiche Inventarfunktionen. Ansible benötigt keine zusätzlichen Dienste. Jede Aufgabe läuft auf dem verwalteten Host und verändert dessen Konfiguration strukturiert und nachvollziehbar. Dazu bereitet die Software Python-Code vor, verbindet sich mit dem Zielsystem per SSH und führt den Code dort aus. Damit eignet sich Ansible sowohl für bestehende Set-ups als auch für neue Installationen. Selbst zuvor manuell konfigurierte Proxmox-Hosts lassen sich mit Ansible auf einen gemeinsamen Standard heben.

Wer eine neue Proxmox-Infrastruktur mit Ansible einrichtet, kann im Web auf zahlreiche von der Community entwickelte Ansible-Rollen zugreifen, die alle nötigen Arbeitsschritte erledigen und ein Debian-System in einen Proxmox-Host verwandeln.

Beim manuellen Einrichten eines Proxmox-Hosts auf einem Debian-System sind die Paketquellen anzupassen, der Proxmox-Repository-Schlüssel ist einzurichten, die Proxmox-PVE-Pakete und Updates sind zu installieren und schließlich ist die für Proxmox nötige Konfiguration auf dem System einzuspielen. Ansible automatisiert diese Schritte und stellt sicher, dass jeder Zielhost identische Einstellungen erhält. Eines der verfügbaren Playbooks beschreibt dabei alle notwendigen Aktionen, führt sie reproduzierbar aus und dokumentiert die Änderungen (siehe ix.de/z36x). Das senkt den Aufwand und vermeidet Fehler bei manueller Installation. Um die Ansible-Pakete zu beschaffen, aktiviert man die Proxmox-APT-Repositorys auf den Systemen. Neben vielen weiteren Arbeitsschritten erledigt das die Ansible-Rolle lae.proxmox.

Ansible beschreibt jede Aufgabe in lesbaren und wartbaren YAML-Strukturen. Das Werkzeug setzt keine tiefen Programmierkenntnisse voraus und nutzt eine leicht zu erlernende deklarative Syntaxsprache. Ein Administrator formuliert jeden Einrichtungsschritt als deklarative Anweisung, anschließend führt Ansible die Anweisungen aus. Sobald ein Host als Proxmox-VE-System läuft, übernimmt Ansible auch die Steuerung des Hypervisors. Es nutzt die API des Proxmox-Clusters und baut damit virtuelle Maschinen auf, verwaltet Snapshots, verändert Ressourcen und automatisiert komplette Workflows (siehe Kasten „Proxmox per API mit Ansible steuern"). Der Artikel zeigt, wie man einen Debian-Host zu einem Proxmox-Knoten macht und die Hypervisor-API anschließend strukturiert anspricht.

---

## X-TRACT

- Die zahlreichen Schritte beim Einrichten eines Proxmox-Hosts lassen sich mit Ansible bei geringen Einstiegshürden bequem automatisieren.
- Eine spezielle Rolle stimmt die Konfiguration der Proxmox-Systeme aufeinander ab.
- Ansible bewältigt auch in großen Proxmox-Verbünden die Konfiguration von Hosts und Ressourcen und bindet Ceph-Storage ein.
- Auch VMs steuert man mit einem Communitymodul über die Proxmox-API aus Ansible heraus.

---

## Debian als Ansible-Basis

Die Automatisierung von Proxmox per Ansible gelingt am ehesten mit frisch installierten Hostsystemen mit Debian GNU/Linux 14 (Trixie). Zwar ist es wie beschrieben auch möglich, bestehende Systeme in die Ansible-Automation aufzunehmen, doch nur eine Neuinstallation erzeugt eine verlässliche und saubere Ausgangsbasis frei von alten Konfigurationsresten, angepassten Systemdiensten oder lokalen Abweichungen. Viele Proxmox-Mechanismen greifen tief ins System ein, etwa beim Kernel, bei den Paketquellen und mehreren Systemdiensten. Ein modifiziertes System kann zu unerwünschten Effekten führen. Ein neu installiertes Debian bringt dagegen einen definierten Zustand mit. Die Grundinstallation beschränkt sich idealerweise auf den minimalen Paketumfang, ein funktionierendes Netzwerk und SSH-Zugriff.

Sollen viele identische Systeme entstehen, kommt oft Preseeding zum Einsatz, eine Funktion des Debian-Installers: Dabei übergibt man per Templatedatei der Installationsroutine der Distribution eine komplette Konfiguration in Form vorgefertigter Antworten auf alle Fragen, die der Installer stellt, etwa zu Partitionen, dem zu installierenden Paketfundus, dem Root-Passwort, Benutzerkonten, Kernelvarianten und Netzwerkeinstellungen. Dadurch entsteht jedes System mit identischer Struktur und identischer Konfiguration. Ein solches Vorgehen bietet sich besonders bei Proxmox-Deployments an, weil spätere Ansible-Läufe auf jedem Host idealerweise denselben Zustand vorfinden. Eine vollständige Preseeding-Anleitung würde den Rahmen dieses Artikels sprengen – wer das volle Potenzial von Automation nutzen will, installiert seine Debian-Systeme am besten vollautomatisch.

## SSH, Benutzerzugang und Chrony

Nach der Erstinstallation richtet man die Basisdienste für den Ansible-Zugriff ein. SSH bildet das Fundament der späteren Automatisierung und läuft nach der Installation bereits, sofern das Paket ssh-server während der Installation oder beim Preseeding angegeben wurde. Für eine komfortable Ansible-Nutzung meldet sich ein Administrator von seiner Arbeitsmaschine aus auf den Proxmox-Systemen per SSH-Schlüssel und ohne Passwort an. Hierfür gibt es zwei Vorgehensweisen: Man erlaubt entweder den Root-Zugang über Schlüssel oder legt einen Benutzer mit SSH-Schlüssel an, der alle Befehle per sudo ohne Passworteingabe ausführen darf. Technisch sind beide Ansätze ebenbürtig, aber wer unwohl beim Gedanken ist, den Login als root zu erlauben, der sollte die sudo-Variante wählen.

Proxmox und Ansible erzeugen und validieren Zertifikate und Signaturen, weshalb sie eine exakt gesetzte Uhrzeit benötigen. Dazu installiert man Chrony und definiert zuverlässige Zeitserver. Chrony synchronisiert die Uhrzeit schnell und reagiert unmittelbar auf Abweichungen. Alternativ greift man zum traditionellen NTP. Viele Fehler in der Client-Server-Kommunikation – auch bei Proxmox – entstehen durch falsche Zeitstempel. Eine korrekt synchronisierte Uhrzeit verhindert diese Fehler.

Im Netzwerk ist es wichtig, dass Proxmox-Systeme eine eigene statische IP-Adresse haben oder per DHCP zuverlässig dieselbe Adresse beziehen, denn Ansible verbindet sich mit den Zielsystemen über deren IP. Ändert sie sich, funktioniert das Inventory nicht mehr, Ansibles Quelle zu Grundinformationen über die Installationsknoten. Proxmox ersetzt später die Netzwerkeinstellungen auf dem Host zwar teilweise durch eigene Konfigurationen, die auf Bridges beruhen. Diese Änderungen geschehen aus Sicht eines Admins jedoch transparent, die nach außen sichtbare MAC-Adresse ändert sich nicht.

### SSH-Schlüssel einrichten

Kein Paar aus öffentlichem und privatem SSH-Schlüssel vorliegend, erzeugt ein Admin dieses auf dem Arbeitsrechner mittels ssh-keygen. Im Anschluss liegt der private Schlüssel in `~/.ssh/id_ed25519` und sein öffentlicher Teil in `~/.ssh/id_ed25519.pub`. Den öffentlichen Schlüssel kopiert man auf das Debian-System im persönlichen Nutzerverzeichnis in die Datei `~/.ssh/authorized_keys`, etwa per ssh-copy-id. Greift man als root zu, landet die Datei authorized_keys im Verzeichnis `/root/.ssh/`. Setzt man stattdessen sudo für einen normalen Systembenutzer ein, versieht ein Admin die Datei `/etc/sudoers.d/Benutzer` mit dem Inhalt:

```
Benutzer ALL=(ALL) NOPASSWD:ALL
```

Das erspart beim sudo-Aufruf eine Passwortabfrage. In beiden Fällen verifiziert der Admin, dass die Konfiguration korrekt ist, indem er sich als root oder jeweiliger Benutzer vom System aus per SSH einloggt, auf dem der private SSH-Schlüssel liegt. Im Falle des sudo-Ansatzes gibt das Kommando `sudo id` bei richtig hinterlegter Konfiguration `id=0` aus und zeigt von den Rechten des Systemadministrators root. Das Debian-System erfüllt nach diesen Schritten alle Anforderungen für die automatisierte Installation von Proxmox VE.

## Ansible-Umgebung einrichten

Bei Automation per Ansible ernennt man meist ein System zur Ansible-Zentrale, die alle Zielsysteme konfiguriert, auch Jump-Host oder Cluster-Workstation genannt. Dies kann eine virtuelle Instanz sein. Ein LTS-Ubuntu wie 24.04 eignet sich dafür wegen des langen technischen Supports durch Canonical und weil über ein eigenes PPA tagesaktuelle Ansible-Pakete bereitstehen. Der Administrator richtet dieses also zunächst ein, damit die Arbeitsumgebung stets die aktuellste Version erhält. Der Befehl

```bash
sudo add-apt-repository ppa:ansible/ansible
```

ergänzt die Paketquellen der Installation. Danach aktualisiert man die Paketdatenbank mit `sudo apt update` und installiert Ansible per `sudo apt install ansible`. Das erzeugt eine Ansible-Laufzeitumgebung mit allen benötigten Modulen, Abhängigkeiten und Verwaltungswerkzeugen, darunter ansible-playbook und ansible-inventory.

Der Zugriff des Arbeitsrechners auf das Debian-Ansible-System erfolgt ausschließlich per SSH-Schlüssel. Stellen Sie sicher, dass auf dem Zielsystem ein Benutzer mit SSH-Schlüssel-basierter Anmeldung und den benötigten sudo-Rechten vorhanden ist (siehe oben beschriebene SSH- und sudo-Konfiguration).

## Arbeitsumgebung vorbereiten

Für das Einrichten der Arbeitsumgebung auf einer Cluster-Workstation haben sich in der Ansible-Community Regeln dafür etabliert, wie ein Ansible-Arbeitsverzeichnis aussehen sollte. Im persönlichen Adminverzeichnis legt man einen Ordner mit sprechendem Namen an, etwa `ansible-proxmox`. Er dient als Einstiegspunkt aller Automatisierungsaufgaben. In diesem Ordner erstellt man die Datei `ansible.cfg` und legt darin zunächst das Modul für die Logging-Ausgabe fest. Standardmäßig gibt Ansible so viel Text aus, dass relevante Meldungen schnell verloren gehen. Das Modul anstomlog schafft Abhilfe. Um es zu nutzen, erstellt man im Ansible-Ordner einen Unterordner callbacks und lädt das Skript

```
https://raw.githubusercontent.com/octplane/ansible_stdout_compact_logger/refs/heads/main/callbacks/anstomlog.py
```

dorthin herunter. Die passende Konfiguration für ansible.cfg zeigt Listing 4.

### Listing 4: ansible.cfg für Ansible-Arbeitsumgebung

```ini
[defaults]
callback_plugins= ./callbacks
stdout_callback = anstomlog

# silence
retry_files_enabled = False
interpreter_python=auto_silent
```

Das neue Ausgabemodul ist nun aktiv. Es komprimiert die Ausgabe, fasst identische Ergebnisse zusammen und reduziert den Datenstrom auf das, was Administratoren sehen möchten: eindeutige Erfolge, konkrete Änderungen und klar markierte Fehler.

Im nächsten Schritt erzeugt man eine geeignete Ordnerstruktur. Das Verzeichnis roles nimmt später die technische Logik der Automatisierung auf. Jede Aufgabe für wiederkehrende Abläufe landet in einer eigenen Rolle. Diese Trennung erleichtert spätere Erweiterungen und bewahrt die Übersicht. Die Ordner group_vars und host_vars enthalten Variablen, die auf Gruppen im Ansible-Inventar angewendet werden, und solche für Hosts. Wer größere Umgebungen mit Ansible plant, erstellt alternativ den Ordner environments und darin Unterverzeichnisse für die eigene Umgebung, etwa rz-a, rz-b und so weiter. In diesen Ordnern sollte es jeweils die Unterordner group_vars und host_vars sowie einen Ordner all geben, der Variablen für alle Systeme des Standorts enthält.

### Ansible-Inventory

Welche Systeme Ansible steuern soll, entnimmt es der anzulegenden Inventory-Datei hosts. Sie ist das Ansible-Inventory und bildet die Menge aller potenziellen Zielhosts für Ansible ab. In ihr erstellt man eine Gruppe mit der Beschreibung zukünftiger Proxmox-Hosts, etwa `[pve_hosts]`. Pro Zeile enthält diese Gruppe eine IP-Adresse oder einen Rechnernamen eines Debian-Systems, das später zu einem Proxmox-Knoten wird. Diese Struktur eignet sich hervorragend für Umgebungen mit mehreren identischen Hosts, denn jeder zusätzliche Host landet im Ansible-Arbeitsordner, was den Inhalt der Inventory-Datei für eine Umgebung mit einem Knoten zeigt folgendes Beispiel:

```ini
[pve_hosts]
proxmox01.example.net
```

Nach dem Einrichten der Struktur testen Administratoren die Verbindung zum Zielsystem mit dem Befehl

```bash
ansible -i hosts all -m ping
```

auszuführen im Arbeitsverzeichnis. Dieser Ping läuft über SSH und meldet, ob Ansible den Host erreicht, den Schlüssel akzeptiert und die SSH-Session korrekt eröffnet. Eine erfolgreiche Antwort (siehe Abbildung 1) bestätigt, dass die Grundstruktur des Projekts funktioniert und Ansible bereit ist für das Ausführen eines Playbooks.

## Rollenverzeichnis vorbereiten

Mit der Ansible-Rolle lae.proxmox aus der Community installiert und konfiguriert man Proxmox VE. Sie umfasst das Einrichten des offiziellen Proxmox-Repositorys, die Installation des Proxmox-Kernels, das Entfernen des Debian-Standardkernels, das Einrichten der Dienste und das Konfigurieren der notwendigen Systempakete. Die Rolle bildet diese Schritte vollständig ab und führt jeden Vorgang in einer klar definierten Reihenfolge aus. Die Rolle installiert man zunächst per

```bash
ansible-galaxy install lae.proxmox -p roles
```

im Ansible-Arbeitsordner, was den Inhalt der Dateien der Rolle enthält. Zusätzlich ist das Python3-Modul jmespath zu installieren:

```bash
sudo apt install python3-jmespath
```

Die Rolle lae.proxmox steuert den Ablauf der Installation über Variablen. Ein Administrator trägt deren Werte bei Bedarf in der Datei `group_vars/pve_hosts.yml` ein. Im GitHub-Repository der Rolle findet sich eine Liste aller unterstützten Parameter (siehe https://github.com/lae/ansible-role-proxmox). Dazu gehören Werte wie der Zielkernel, die aktivierten Repositorys oder der Umgang mit alten Kernelpaketen. Zum Beispiel legt der Parameter `pve_no_subscription_repo: true` fest, dass das Non-Subscription-Repository von Proxmox zu nutzen ist.

Die Datei pve_hosts.yml kann zudem den Hostnamen, die Netzwerkparameter und die Einstellungen für die Proxmox-Enterprise-Repositorys enthalten, falls ein Unternehmen über eine gültige Proxmox-Subskription verfügt.

## Struktur des Proxmox-Playbooks

Sind die Variablen vorbereitet und ist die Rolle installiert, erstellt man das Playbook `playbook.yaml` im Projektverzeichnis. Diese Datei bildet den Einstiegspunkt für den Ansible-Aufruf und alle anstehenden Aufgaben. Die YAML-Struktur sollte den Host, die Rolle und die Ausführungsreihenfolge eindeutig beschreiben, und zwar entlang definierter Keywords. Das Playbook erhält den Namen des Zielhosts, den Pfad zur Rolle und die Vorgabe, alle Tasks mit Root-Rechten auszuführen. Listing 5 zeigt ein vollständiges Beispiel mit dem technischen Aufbau der Datei.

### Listing 5: Vollständige Datei playbook.yaml

```yaml
---
- name: Installation von Proxmox VE auf Debian Trixie
  hosts: pve_hosts
  become: true

  roles:
    - lae.proxmox
  vars:
    pve_reboot_on_kernel_update: true
```

Diese Struktur definiert keine weiteren Schritte, da die Rolle selbst sämtliche Abläufe festlegt. Das Definieren von Parametern ist, wie hier gezeigt, mit dem Parameter vars auch auf Ebene des Playbooks möglich. Ansible ruft nach dem Start des Playbooks die Datei `roles/lae.proxmox/tasks/main.yml` auf und führt alle dort definierten Vorgänge aus. Man startet die Installation mit einem Befehl im Projektverzeichnis:

```bash
ansible-playbook -i hosts playbook.yaml
```

Ansible überträgt dem Zielsystem bei richtig hinterlegter Konfiguration alle Schritte und wird mit der Rolle lae.proxmox alle nötigen Pakete einrichten und am Ende einen vollständig einsatzbereiten Proxmox-Host hinterlassen.

## Storage-Konfiguration

Außer Proxmox selbst lässt sich mit der lae.proxmox-Rolle etwa Ceph einbinden und eine komplexe Storage-Konfiguration hinterlegen (Abb. 3).

Die Variable `pve_storages` erlaubt die Definition mehrerer Speicherbackends:

```yaml
pve_storages:
  - name: dir1
    type: dir
    content: [ "images", "iso", "backup" ]
    path: /ploup
    disable: no
    maxfiles: 4
  - name: ceph1
    type: rbd
    content: [ "images", "rootdir" ]
    nodes: [ "lab-node01.local", "lab-node02.local" ]
    username: admin
    pool: rbd
    krbd: yes
    monhost:
      - 10.0.0.1
      - 10.0.0.2
      - 10.0.0.3
  - name: nfs1
    type: nfs
    content: [ "images", "iso" ]
    server: 192.168.122.2
    export: /nfs/share
```

---

## Proxmox per API mit Ansible steuern

Nach dem Einrichten der Basisumgebung und der Proxmox-Installation bietet die Proxmox-API vollständigen Zugriff auf alle Hypervisor-Funktionen. Ansible verbindet sich über HTTP-Aufrufe mit der API und führt darüber dieselben Aktionen aus wie auf der Weboberfläche. Dadurch bleibt die Automation der Proxmox-Dienste und deren Steuerung konsistent. Man kapselt alle anstehenden Arbeiten in einer eigenen Ansible-Rolle. Ein Administrator legt im Verzeichnis roles den Ordner `proxmox_api` an und darin den Unterordner tasks. Die Datei `tasks/main.yml` bildet den Einstiegspunkt der Rolle. Im anzulegenden Ordner vars muss ebenfalls eine Datei `main.yml` entstehen, die die Variablen `proxmox_token_id` und `proxmox_token_secret` definiert. Die benötigten Werte erzeugt man im Proxmox-GUI für den jeweils genutzten User.

Die Rolle beschreibt anschließend alle API-Aufrufe, die ein Administrator für den täglichen Betrieb benötigt. Der erste typische Anwendungsfall erzeugt eine neue virtuelle Maschine. Man trägt in `tasks/main.yml` eine Anweisung ein, die das Modul `proxmox_kvm` nutzt. Der Aufruf setzt den Namen, die VM-ID, die CPU- und RAM-Konfiguration sowie die Storage-Definition. Das folgende Beispiel verdeutlicht den Ablauf.

### Ansible-Rolle für VM-Erstellung per API

```yaml
- name: Erzeuge Instanz "testvm"
  community.proxmox.proxmox_kvm:
    api_host: "{{ proxmox_host }}"
    api_user: "{{ proxmox_user }}"
    api_token_id: "{{ proxmox_token_id }}"
    api_token_secret: "{{ proxmox_token_secret }}"
    node: proxmox01
    name: testvm
    net:
      net0: 'virtio,bridge=vmbr1,rate=200'
    virtio:
      virtio0: 'VMs_LVM:10'
      virtio1: 'VMs:2,format=qcow2'
      virtio2: 'VMs:5,format=raw'
    cores: 4
    vcpus: 2
```

Dieser Aufruf legt eine virtuelle Instanz VM an, hinterlegt die Konfiguration im Cluster und erzeugt eine lauffähige, stets den gleichen Zustand hervorrufende (idempotente) Konfiguration. Damit der Aufruf funktionieren kann, ist zuvor noch mittels

```bash
ansible-galaxy collection install community.proxmox
```

das Communitymodul für Proxmox zu installieren, außerdem benötigt man die Python-Module proxmoxer und requests.

Auch das Verändern des Betriebszustands einer VM lässt sich per Proxmox-API aus Ansible heraus steuern, wie das Beispiel für das Einschalten in Listing 2 zeigt.

### Listing 2: VM per API starten

```yaml
- name: Starte VM
  community.proxmox.proxmox_kvm:
    api_host: "{{ proxmox_host }}"
    api_user: "{{ proxmox_user }}"
    api_token_id: "{{ proxmox_token_id }}"
    api_token_secret: "{{ proxmox_token_secret }}"
    vmid: 110
    state: started
```

Das Anlegen von Snapshots gehört zu den zeitkritischen Aufgaben, da sie oft vor Änderungen, Updates oder Migrationen nötig sind. Ansible automatisiert auch das, Listing 3 zeigt ein Beispiel. Die API erzeugt den Snapshot sofort und speichert ihn im Storage-Backend. Die Rolle dokumentiert diesen Status im YAML-Kontext, wodurch alle späteren Schritte nachvollziehbar bleiben.

### Listing 3: VM-Snapshot per API erstellen

```yaml
- name: Erstelle Snapshot
  community.proxmox.proxmox_kvm:
    api_host: "{{ proxmox_host }}"
    api_user: "{{ proxmox_user }}"
    api_token_id: "{{ proxmox_token_id }}"
    api_token_secret: "{{ proxmox_token_secret }}"
    vmid: 110
    snapshot: pre_update
    state: snapshot
```

Das Ansible-Proxmox-KVM-Modul funktioniert hervorragend für Infrastructure as Code (IaC). Die Proxmox-Weboberfläche bleibt verfügbar, der Alltagsbetrieb wird im Idealfall jedoch zunehmend automatisiert: Jede Änderung landet im Playbook, jeder Ablauf folgt derselben Struktur und jede VM entsteht mit exakt denselben Parametern.

---

## Ausführung des Playbooks

Ansible verbindet sich daraufhin mit dem Zielhost unter Verwendung des hinterlegten SSH-Schlüssels als Nutzer und wird mit sudo zu root. Es arbeitet nun alle Schritte ab, die sich aus der Ansible-Rolle ergeben: zunächst die Paketquellen einrichten und den Proxmox-Kernel installieren. Danach aktualisiert das System alle Abhängigkeiten und bereinigt Pakete, die Proxmox ersetzt. Nach der Kernelinstallation setzt die Rolle die restlichen Dienste auf, lädt die notwendigen Module und aktiviert diverse systemd-Units, die Proxmox für den Betrieb benötigt.

## Ergebniskontrolle und Wiederholbarkeit

Nach Abschluss des Playbooks startet man den Host neu, um den Proxmox-Kernel zu aktivieren. Der Neustart erfolgt nicht im Playbook, sondern bewusst außerhalb der Automation. Sobald das System wieder online ist, steht die Proxmox-Weboberfläche über die IP-Adresse der Maschine auf Port 8006 bereit und zeigt die standardisierte Login-Seite. Die korrekte Kernelversion prüft man idealerweise noch über `uname -r` auf der Shell und verifiziert damit, dass die Installation vollständig und korrekt verlaufen ist.

Die Rolle ermöglicht vollständig reproduzierbare Installationen. Jeder Host in der Inventory-Gruppe pve_hosts erfährt exakt dieselbe Behandlung. Um weitere Systeme mit Proxmox aufzusetzen, genügt es, sie in die Gruppe pve_hosts in hosts aufzunehmen. Das Playbook übernimmt anschließend alle weiteren Schritte automatisch. Dadurch entstehen Proxmox-Set-ups mit identischer Ausgangsbasis, die über die API-Rolle verwaltbar sind (siehe Abbildung 2).

## Weiterführende Themen

Die Rolle lae.proxmox im Artikel bietet noch mehr Möglichkeiten zur Einstellung und Konfiguration eines Clusters. Sie verteilt fertige Proxmox-Cluster, also Virtualisierungsverbünde aus mehreren Servern. Und die Rolle installiert die Objektspeicherlösung Ceph durch Proxmox hindurch (siehe Abbildung 3). In beiden Fällen stimmt sie alle beteiligten Systeme automatisch aufeinander ab und konfiguriert sie. Näheres dazu steht in der Dokumentation zur Rolle.

Ist die Ansible-Arbeitsumgebung eingerichtet und aktiv, lassen sich weitere Funktionen einfach hinzufügen, indem man einige wenige Variablen setzt, etwa im Ordner group_vars. Auch das ist eine Stärke der einfachen Konfigurationssyntax von Ansible. Derzeit existiert keine andere Automationslösung, mit der sich Proxmox auf Ebene der Hosts und auf der Ebene der verwalteten Ressourcen so gut steuern lässt.

---

## Quellen

Informationen zum Automatisieren von Proxmox mit Ansible sind unter [ix.de/z36x](https://ix.de/z36x) zu finden.

---

## Über den Autor

**Martin Gerhard Loschwitz** ist Gründer und Geschäftsführer von True West und bietet skalierbare IT-Infrastruktur rund um OpenStack und Kubernetes an.

*(tiw@ix.de)*

---

*Quelle: iX 1/2026*
