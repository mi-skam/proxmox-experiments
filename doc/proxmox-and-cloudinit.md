# Proxmox und Cloud-init: der VM-Konfigurator

*Von Thomas Joos*

Cloud-init stellt für Proxmox neue VM- und Containerinstanzen automatisiert bereit, die individuelle Konfiguration erledigt es beim Booten. Gastsysteme entstehen reproduzierbar und ohne Nacharbeiten.

## Einführung

Die Virtualisierungssoftware Proxmox Virtual Environment (VE) kombiniert KVM-Hypervisor, Container, Software-defined Storage und Netzwerkverwaltung in einer Plattform. Sie gestattet es, den gesamten Lebenszyklus virtueller Maschinen über Webkonsole, Kommandozeile und REST-API zu verwalten. In Clusterumgebungen orchestriert Proxmox die Bereitstellung von VMs und Containern mit zentralem Dateisystem und rollenbasiertem Zugriff. Automatisierung spielt dabei eine zentrale Rolle. Administratoren erzeugen neue Instanzen nicht mehr manuell, sondern über standardisierte Prozesse, die Netzwerk, Benutzer, Pakete und Dienste direkt beim Start einer VM konfigurieren. Das Open-Source-Tool Cloud-init dient als Schnittstelle zwischen Basisimage und Konfiguration.

Ein typisches Szenario für den Einsatz von Cloud-init sind Serienbereitstellungen identischer Systeme. Statt Dutzende Instanzen einzeln anzulegen, nutzt ein Administrator ein vorbereitetes Template mit integriertem Cloud-init-Laufwerk. Netzwerkeinstellungen, SSH-Schlüssel, Hostnamen und Pakete entstehen automatisch beim ersten Bootvorgang. So baut man reproduzierbare Umgebungen auf, die ohne manuelle Nacharbeit sofort funktionsfähig sind.

## Grundlagen und Templates

Cloud-init gilt als De-facto-Standard für die automatisierte Initialisierung von Cloud-Instanzen. Das Open-Source-Tool liest Konfigurationsdaten aus Metadatenquellen, die die Virtualisierungsumgebung bereitstellt. In Proxmox stellt man die Quellen über ein virtuelles CD-ROM-Laufwerk mit einem ISO-Image zur Verfügung, auf dem sich die Dateien user-data und meta-data befinden.

Beim ersten Start liest der Cloud-init-Agent in der virtuellen Instanz diese Informationen und führt sie systemweit aus. Unter Linux verwendet Proxmox das Format nocloud mit einfacher YAML-Struktur für die Cloud-init-Konfiguration. Für Windows gibt es die angepasste Cloudbase-Init-Variante mit dem Format configdrive2. Beide Mechanismen verfolgen dasselbe Ziel: die Übergabe von Parametern an die Instanz beim Bootvorgang. In Linux-Umgebungen wertet systemd die Parameter aus, in Windows tun das die Cloudbase-Dienste.

Die Grundlage einer automatisierten Bereitstellung ist ein vorkonfiguriertes Basisimage. Viele Distributionen stellen fertige Cloud-Images bereit, zum Beispiel Ubuntu unter cloud-images.ubuntu.com. Diese Images sind bereits mit dem Cloud-init-Paket ausgestattet. Nach dem Herunterladen importiert man das Image in Proxmox mit dem Befehl `qm` (QEMU Manager).

### Beispiel: VM erstellen und Image importieren

```bash
qm create 106
```

Erzeugt in der Proxmox-Shell eine neue VM mit der ID 106. Das heruntergeladene Image bindet man anschließend ein mit:

```bash
qm importdisk 106 oracular-server-cloudimg-amd64.img local-lvm
```

Die Befehle `qm` und `pct` bilden die zentrale Schnittstelle zur Verwaltung virtueller Maschinen und Container in Proxmox VE. Der Befehlssatz von `qm` dient zur Steuerung klassischer VMs, die auf dem KVM-Hypervisor laufen. Darüber lassen sich Instanzen anlegen, starten, stoppen, klonen und mit Cloud-init konfigurieren. Der Befehlssatz von `pct` (Proxmox Container Toolkit) erledigt dieselbe Aufgabe für Linux-Container und übernimmt Erstellung, Ressourcenverwaltung und Netzwerkanbindung. Beide Werkzeuge haben eine ähnliche Syntax, man führt sie in der Proxmox-Shell aus.

In Proxmox führt man Systembefehle entweder direkt über die integrierte Shell in der Weboberfläche oder per SSH-Verbindung zum Host aus. Die integrierte Shell befindet sich im linken Menü unter dem Knoten der Instanz (rechte Maustaste, dann Shell). Alternativ lässt sich der Host von einem anderen Rechner aus mit einem SSH-Client oder über das Terminal mit `ssh root@<IP-Adresse>` verbinden.

Nach der Anmeldung steht die Linux-Konsole des Proxmox-Servers zur Verfügung, in der sämtliche `qm`- und `pct`-Befehle ausgeführt werden.

Der Import bindet das Image an den angegebenen Speicher. Anschließend wählt man in der Webkonsole unter Hardware die Festplatte und ordnet sie dem SCSI-Controller zu. Die Startreihenfolge prüft man unter Optionen. Der Wert `order=any` stellt sicher, dass die VM von der neuen Disk startet, danach folgt der Schritt Hardware/Hinzufügen/Cloudinit-Laufwerk. Dieses Laufwerk enthält die Metadaten, die Cloud-init beim Start verarbeitet.

Über den Menüpunkt Cloud-init in den VM-Eigenschaften lassen sich Benutzername, Kennwort, SSH-Schlüssel, DNS-Domäne, DNS-Server und die IP-Konfiguration hinterlegen. Optional aktiviert man die Paketaktualisierung. Nach einem Klick auf „Image neu erzeugen" schreibt Proxmox die Metadaten in das ISO-Laufwerk für die VM. Beim Start der VM wendet Cloud-init diese Konfiguration an und initialisiert das System mit den gewünschten Werten.

Eine Vorlage (Template) enthält bereits das Betriebssystem und die Cloud-init-Konfiguration, die beim ersten Start automatisch ausgeführt wird. Der Befehl `qm set <vmid>` definiert Parameter wie Benutzername, SSH-Schlüssel oder Netzwerkeinstellungen. Diese Werte schreibt Proxmox in die Metadaten des Cloud-init-Laufwerks, das der virtuellen Maschine zugeordnet ist. Beim ersten Bootvorgang liest der Cloud-init-Agent der virtuellen Maschine diese Daten aus und wendet sie systemweit an.

Vorlagen beschleunigen das Bereitstellen erheblich. Eine konfigurierte Instanz wandelt man mit `qm template <vmid>` in eine Vorlage um. Neue VMs entstehen daraus als Linked Clone oder Full Clone. Linked Clones teilen sich die Basisdisk und sparen Speicherplatz, Full Clones erzeugen eigenständige Kopien. Für größere Cluster sind Linked Clones meist effizienter.

## Automatisches Bereitstellen

In einem typischen Szenario legt ein Administrator in einem Proxmox-Cluster eine neue VM für einen Webserver an, der sich selbst konfiguriert und unmittelbar nach dem Start einsatzbereit ist. Ausgangspunkt für das Beispiel ist ein importiertes Ubuntu-Cloud-Image. Die VM wird zuerst mit `qm create` erstellt, `qm importdisk` bindet anschließend die heruntergeladene Imagedatei ein und `qm set` fügt das Cloud-init-Laufwerk hinzu.

### Listing 1: Eine Webserver-VM bereitstellen

```bash
qm create 120 --name web01 --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 120 ubuntu-24.04-server-cloudimg-amd64.img local-lvm
qm set 120 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-120-disk-0 --ide2 local-lvm:cloudinit
```

Im Feld Cloud-init trägt man Benutzername, SSH-Schlüssel und Netzwerkkonfiguration ein, zum Beispiel:

```bash
ipconfig0=ip=10.0.10.50/24,gw=10.0.10.1
```

Nach dem Klick auf „Image neu erzeugen" erstellt Proxmox die Metadaten automatisch. Der erste Bootvorgang ruft die Cloud-init-Module auf, legt das Benutzerkonto an, installiert die Pakete aus dem Abschnitt „packages" und startet den Apache-Dienst. Das System steht danach im Cluster als vollständig vorkonfigurierter Webserver bereit, inklusive korrekt gesetzter Hostnamen und aktiver SSH-Verbindung. Wird das Template in derselben Form mehrfach geklont, entstehen in wenigen Minuten mehrere identische betriebsbereite Systeme. Die Proxmox-Aufgabenansicht zeigt dabei in Echtzeit, wann Cloud-init abgeschlossen ist und wann der Host den ersten erfolgreichen Login akzeptiert.

## Individuelle Konfiguration über cicustom

Neben der GUI-Konfiguration unterstützt Proxmox auch benutzerdefinierte YAML-Dateien über die Option `--cicustom`. Diese teilt die Cloud-init-Dateien in vier Bereiche: `user`, `network`, `meta` und `vendor`. Sie werden in Proxmox als Snippets abgelegt. Snippets sind Textdateien, die im Verzeichnis `/var/lib/vz/snippets/` oder auf entsprechend aktivierten Speichern liegen.

Ein Beispiel:

```bash
qm set 9000 --cicustom "user=local:snippets/userconfig.yaml"
```

bindet eine benutzerdefinierte Datei ein. Diese Datei enthält YAML-Inhalte, die Cloud-init beim Start auswertet. Eine typische YAML-Datei enthält klar strukturierte Parameter für Benutzer, Netzwerk und Systeminitialisierung. Ihr Inhalt legt fest, wie Cloud-init beim ersten Start der VM Benutzerkonten anlegt, Netzwerkschnittstellen konfiguriert und zusätzliche Befehle ausführt.

### Listing 2: Benutzerdefinierte Datei userconfig.yaml

```yaml
# Benutzerkonfiguration
users:
  - name: admin
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAvj6xX...admin@server

# Systemparameter
hostname: app-server01
package_update: true
package_upgrade: true
packages:
  - net-tools
  - htop
  - nginx

# Netzwerkdefinition
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 10.0.0.25/24
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses: [10.0.0.10, 8.8.8.8]

# Startbefehle
runcmd:
  - systemctl enable nginx
  - systemctl start nginx
```

In diesem Beispiel legt der obere Abschnitt den Benutzer admin mit administrativen Rechten und einem SSH-Schlüssel fest. Der Abschnitt packages installiert beim ersten Start mehrere Standardwerkzeuge und aktiviert den nginx-Dienst. Unter network sind IP-Adresse, Gateway und DNS-Server definiert, wodurch die Netzwerkkonfiguration auch ohne DHCP automatisch funktioniert.

Die Datei wird im Speicherbereich snippets hinterlegt und über:

```bash
qm set 9000 --cicustom "user=local:snippets/userconfig.yaml"
```

mit der gewünschten VM verknüpft. Beim ersten Start liest Cloud-init die Datei ein und führt alle Anweisungen automatisch aus.

Ein Administrator exportiert automatisch generierte Konfigurationsdateien mit:

```bash
qm cloudinit dump 9000
```

und nutzt sie als Vorlage für eigene Anpassungen. So bleiben Basistemplate und benutzerdefinierte Parameter getrennt.

## Erweiterte Parameter in Proxmox

Cloud-init integriert sich tief in die VM-Konfiguration. Die Parameter `ciuser`, `cipassword`, `ciupgrade`, `ipconfig[n]`, `sshkeys`, `nameserver` und `searchdomain` setzt man per CLI:

```bash
qm set 9000 --ciuser admin \
  --cipassword "YourSecurePasswordHere" --sshkeys /root/.ssh/id_rsa.pub
```

Die Option `ipconfig0` definiert die Netzwerkschnittstelle. Eine statische IPv4-Adresse wird über:

```bash
ipconfig0=ip=192.168.1.50/24,gw=192.168.1.1
```

gesetzt. Für IPv6 gilt die Syntax `ipconfig0=ip6=auto`.

Beim Passwort-Handling empfiehlt sich die Verwendung von SSH-Schlüsseln. Kennwörter werden im Klartext in der VM-Konfiguration gespeichert, was in produktiven Umgebungen vermieden werden sollte. Proxmox erlaubt den Upload von SSH-Schlüsseln über die Weboberfläche oder das CLI. Beim Start werden sie in die Datei `~/.ssh/authorized_keys` des Zielbenutzers geschrieben.

Bei der Arbeit mit Cloud-init in Proxmox ist die genaue Kontrolle des Initialisierungsvorgangs hilfreich, um Fehler frühzeitig zu erkennen. Der Befehl:

```bash
journalctl -u cloud-init
```

ruft im laufenden System die Protokolle der einzelnen Module ab. Sie zeigen, ob Benutzerkonten, Netzwerke und Pakete korrekt angewendet wurden.

Cloud-init arbeitet modular in mehreren Phasen, beginnend mit der lokalen Initialisierung, gefolgt von der Netzwerkkonfiguration, der Benutzererstellung und abschließend den benutzerdefinierten Skripten aus dem Abschnitt `runcmd` in der Konfigurationsdatei. Diese Struktur erleichtert es, Fehler einzugrenzen und gezielt zu beheben. In Proxmox lassen sich außerdem mehrere Netzwerkschnittstellen parallel über Parameter wie `ipconfig1`, `ipconfig2` und so weiter definieren. Für komplexe Umgebungen mit VLANs, Bonds oder Bridges unterstützt Cloud-init in Verbindung mit Proxmox die automatische Integration in bestehende SDN-Zonen (Software-defined Networking). Wird die Proxmox-SDN-Funktion genutzt, ordnet das System die Schnittstellen automatisch den vordefinierten Netzsegmenten zu.

## Windows-Integration mit Cloudbase-Init

Für Windows-Instanzen kommt Cloudbase-Init zum Einsatz, eine native Portierung des Cloud-init-Frameworks. Die Integration erfolgt durch Installation des Pakets in einem vorbereiteten Windows-Template. Nach der Installation wird das System mit Sysprep generalisiert und als Vorlage gespeichert.

Vor der Sysprep-Ausführung konfiguriert man Cloudbase-Init, wichtige Parameter sind `metadata_services`, `allow_reboot` und `rename_admin_user`. Cloudbase-Init liest anschließend die Metadaten von Proxmox, erstellt Benutzer, setzt Kennwörter, aktiviert RDP, konfiguriert Netzwerke und schreibt Logeinträge nach `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log`. Nicht benötigte Komponenten wie OneDrive sollte man vor der Templateerstellung entfernen.

Das Ergebnis ist ein wiederverwendbares Windows-Template, das beim Start automatisch die VM-spezifischen Parameter anwendet. Dadurch lassen sich Windows-Server oder Workstations mit denselben Automatisierungsmechanismen wie Linux-Systeme bereitstellen.

## Containerumgebungen mit LXC

Außer KVM-Instanzen lassen sich auch Linux-Container in Proxmox weitgehend automatisiert bereitstellen. Das Containerframework LXC nutzt dafür vorkonfigurierte Images, die über die Proxmox-Weboberfläche oder per CLI geladen werden.

### Listing 3: Einen LXC-Container erstellen

```bash
pct create 201 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
  --hostname app01 --memory 2048 --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --rootfs local-lvm:10
```

### Listing 4: Container automatisiert bereitstellen

```bash
pct create 220 local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst \
  --hostname db01 --cores 2 --memory 2048 --net0 name=eth0,bridge=vmbr1,ip=10.0.20.5/24,gw=10.0.20.1 \
  --rootfs local-lvm:8 \
  --unprivileged 1 --password "YourStrongPasswordHere"
```

Der Ablauf im Detail:
- `pct create 220` weist Proxmox an, einen neuen Container mit der ID 220 anzulegen.
- `local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst` bezeichnet die Vorlage, aus der der Container erstellt wird. Das Template liegt auf dem lokalen Storage local im Verzeichnis vztmpl und enthält ein minimales Ubuntu 24.04.
- `--hostname db01` setzt den Hostnamen des Containers auf db01. Dieser Name wird im Container und im Proxmox-Verzeichnis angezeigt.
- `--cores 2` reserviert zwei virtuelle CPU-Kerne des Hosts für diesen Container.
- `--memory 2048` weist dem Container zwei GByte Arbeitsspeicher zu.
- `--net0 name=eth0,bridge=vmbr1,ip=10.0.20.5/24,gw=10.0.20.1` richtet die Netzwerkschnittstelle. Die Option erstellt eine virtuelle Netzwerkkarte eth0, verbindet sie mit der Bridge vmbr1, vergibt die statische IP-Adresse 10.0.20.5 mit der Netzmaske /24 und legt 10.0.20.1 als Standardgateway fest.
- `--rootfs local-lvm:8` definiert den Speicherort und die Größe des Root-Dateisystems. Es wird auf dem lokalen LVM-Storage angelegt und erhält eine Kapazität von 8 GByte.
- `--unprivileged 1` sorgt dafür, dass der Container als unprivilegierter LXC läuft. Dadurch wird der Root-Benutzer innerhalb des Containers nicht mit Root-Rechten auf dem Host verbunden.
- `--password "SecurePass123"` setzt das Kennwort für den Root-Zugang des Containers. Nach der Erstellung meldet man sich damit über die Proxmox-Konsole oder per SSH an.

Nach dem Ausführen des Befehls legt Proxmox alle Konfigurationsdateien unter `/etc/pve/lxc/220.conf` an, erstellt das Root-Dateisystem, richtet die Netzwerkschnittstelle ein und meldet den Container in der Verwaltungsoberfläche an. Anschließend kann man ihn mit `pct start 220` starten.

Nach dem Anlegen wird der Container automatisch gestartet und kann sofort Befehle ausführen. Über:

```bash
pct exec 220 -- apt update && apt install -y mariadb-server
```

lassen sich Installationen oder Konfigurationsänderungen ohne manuelle Anmeldung ausführen.

## Templates, Hookskripte und Backup

Für umfangreiche IT-Umgebungen empfiehlt es sich, Containertemplates vorzubereiten, die bereits alle Pakete und Basisdienste enthalten. Diese Vorlagen lassen sich mit einem Befehl mehrfach klonen:

```bash
pct clone 220 230 --hostname db02
```

Kombiniert man diesen Ansatz mit der REST-API und einem Skript in Python oder Bash, lassen sich Dutzende Container in kurzer Zeit mit identischen Einstellungen erzeugen. Die Integration in das Software-defined-Networking-Modul von Proxmox sorgt dabei für konsistente Netzwerkzuweisungen, da neue Container automatisch in die konfigurierten virtuellen Netze aufgenommen werden.

Hookskripte verfeinern auch hier die Bereitstellung. Beim Starten oder Stoppen eines Containers führen sie benutzerdefinierte Aktionen aus, etwa das Einbinden zusätzlicher Volumes, das Schreiben von Logeinträgen in zentrale Systeme oder das Senden von Webhooks an Überwachungstools. Ein Shellskript `/var/lib/vz/snippets/lxc-start.sh` könnte zum Beispiel beim Start eines Containers automatisch einen Eintrag in eine Inventardatenbank schreiben oder ein Konfigurationsrepository aktualisieren.

Ein wichtiger Aspekt ist die Verbindung von Cloud-init mit der Proxmox-Backup- und Replikationsinfrastruktur. Wer eine auf Cloud-init basierende Vorlage regelmäßig sichert, kann daraus automatisiert wiederherstellbare Systemzustände erzeugen, die bei Bedarf als Ausgangspunkt für neue Instanzen dienen. In Kombination mit der Proxmox-Backup-Integration kann ein Administrator vollständige, inkrementelle oder differenzielle Sicherungen planen, die alle Cloud-init-Metadaten einschließen. Bei einer Wiederherstellung bleibt die Verknüpfung der Cloud-init-Parameter erhalten, wodurch auch geklonte Systeme beim Neustart sofort wieder korrekt konfiguriert sind.

Empfohlen ist außerdem ein Snapshot vor dem Sysprep-Prozess, um bei Fehlschlägen schnell zurückkehren zu können.

Hookskripte erweitern den Lebenszyklus einer VM. Der Parameter `--hookscript` bindet ein Skript an Ereignisse wie Start, Stop oder Clone. Administratoren hinterlegen darin eigene Routinen, die vor oder nach bestimmten Aktionen laufen, etwa einen Monitoring-Trigger, eine Netzwerkanpassung oder eine Anbindung an ein externes Ticketsystem.

Die Proxmox-API erreicht man unter `https://<host>:8006/api2/json`. Mit ihr erstellt, konfiguriert und startet man virtuelle Maschinen. Befehle wie:

```bash
pvesh create /nodes/pve/qemu
```

lassen sich in Automatisierungsskripten einsetzen. Mit den Parametern `onboot` und `startorder` steuern Administratoren die Startreihenfolge mehrerer Instanzen innerhalb eines Hostsystems. Cloud-init, QEMU-Agent und Hookskripte greifen dabei ineinander: Cloud-init kümmert sich um den initialen Aufbau der VM, der Guest-Agent liefert Laufzeitinformationen und Hookskripte erledigen Zusatzaufgaben.

Nach der Containererstellung stehen dieselben Automatisierungsfunktionen wie bei virtuellen Maschinen zur Verfügung. Über die Datei `/etc/pve/lxc/201.conf` lassen sich Startparameter, Ressourcengrenzen und Netzwerkeinstellungen definieren. LXC-Container starten in Sekunden und können ebenfalls durch das Einbinden von Skripten und Hooks automatisiert konfiguriert werden. In Kombination mit Cloud-init bauen Administratoren damit gemischte Umgebungen auf, in denen Container über Ansible oder die REST-API parallel zu VMs provisioniert werden.

Ein vollständiger Automatisierungsablauf beginnt häufig mit dem Herunterladen eines Templates, gefolgt von der Konfiguration in einem Skript.

## Best Practices

Automatisierung mit Cloud-init erfordert präzise Planung. Ein häufiger Fehler liegt in der falschen Platzierung von Snippets auf Clustern. Da Proxmox Cluster-Dateisysteme über Corosync synchronisiert, müssen Snippets auf jedem Node verfügbar sein. Fehlende Pfade führen zu unvollständigen Initialisierungen. Ein weiterer Punkt betrifft die Abhängigkeit zwischen BIOS-Typ und Bootreihenfolge. UEFI-basierte Templates benötigen den korrekten Bootloader-Eintrag.

## Alternative Mechanismen

Neben Cloud-init gibt es in Proxmox noch weitere Automatisierungsoptionen. Der QEMU-Guest-Agent stellt einen Kommunikationskanal zwischen Host und Gast bereit, über den sich Statusinformationen wie IP-Adressen oder Festplattenbelegung abfragen und Befehle im Gastsystem ausführen lassen. Dienste wie Backup, Snapshot und Live-Migration nutzen diese Schnittstelle, um konsistente Zustände zu erreichen.

Cloud-init lässt sich über die REST-API von Proxmox VE in externe Orchestrierungsumgebungen einbinden. Plattformen wie Terraform, Ansible oder SaltStack können über die Endpunkte `/api2/json/nodes/<node>/qemu` automatisiert VMs erstellen, Cloud-init-Parameter setzen und Instanzen starten. Die API-Steuerung macht große Rollouts reproduzierbar, da jede VM mit identischem Befehlssatz und gleichen Metadaten erzeugt wird.

In Terraform spricht man die API über Provider-Module an und verwaltet Variablen wie Hostnamen, IP-Adressen oder SSH-Schlüssel zentral. Ansible-Playbooks können auf dieselbe Weise über das Modul `proxmox_kvm` Cloud-init-Optionen einfügen und Templates instanziieren. Die Kombination dieser Tools mit Cloud-init ermöglicht es, ganze Test- oder Produktionslandschaften aus Code heraus ohne die Proxmox-Oberfläche aufzubauen.

---

## Zusammenfassung (X-TRACT)

- Cloud-init stellt automatisch identische Systeme in großer Zahl bereit.
- Der Cloud-init-Agent muss im Gastbetriebssystem laufen, viele Hersteller bieten vorbereitete Images an.
- Zusammen mit Proxmox hilft Cloud-init beim reproduzierbaren Bereitstellen virtueller Maschinen mit KVM und von LXC-Containern.
- Benutzerdefinierte Konfiguration und Individualisierung ist über YAML-Konfigurationsdateien möglich.

---

## Quellen

Weitere Informationen zu Cloud-init unter [ix.de/z9f1](https://ix.de/z9f1)

---

## Über den Autor

**Thomas Joos** ist freiberuflicher Autor, Trainer und IT-Consultant. Er berät Unternehmen in den Bereichen Microsoft-Netzwerke, Security, KI und Cloud.

*Quelle: iX 1/2026*
