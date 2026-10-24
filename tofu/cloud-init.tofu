# -----------------------------------------------------------------------------
# Einrichtung der Team-VM beim ersten Boot
#
# Ersetzt das fruehere Packer-Image (ADR 0010 im deployment-Repo).
# cloud-init legt die Linux-Nutzer an und die Dateien aus tofu/files/ ab,
# online-ide-setup.sh installiert danach JDK, code-server und nginx.
#
# Die Konfiguration wird mit yamlencode gebaut statt als Template: yamlencode
# quotet jeden Wert selbst, auch Teamnamen mit "#" oder ":".
# -----------------------------------------------------------------------------

locals {
  app_files = [
    for f in sort(fileset("${path.module}/files", "**")) : {
      path        = "/opt/online-ide/${f}"
      encoding    = "gz+b64"
      content     = base64gzip(file("${path.module}/files/${f}"))
      permissions = endswith(f, ".sh") ? "0755" : "0644"
    }
  ]

  cloud_init_config = {
    for team in local.teams_list : team => {
      ssh_pwauth = true

      users = [
        for uid in local.team_members[team] : {
          name        = local.users_map[uid].username
          shell       = "/bin/bash"
          sudo        = ["ALL=(ALL) ALL"]
          lock_passwd = false
        }
      ]

      chpasswd = {
        expire = false
        users = [
          for uid in local.team_members[team] : {
            name     = local.users_map[uid].username
            password = random_password.user_passwords[uid].result
            type     = "text"
          }
        ]
      }

      write_files = concat(
        local.app_files,

        [
          {
            path        = "/etc/online-ide/users"
            permissions = "0644"
            content = join("", [
              for uid in local.team_members[team] : "${local.users_map[uid].username} ${local.user_ports[uid]}\n"
            ])
          },
        ],

        # Das Passwort fuer code-server; das Setup-Skript loescht die Dateien,
        # sobald die Konfiguration geschrieben ist.
        [
          for uid in local.team_members[team] : {
            path        = "/etc/online-ide/passwords/${local.users_map[uid].username}"
            permissions = "0600"
            content     = random_password.user_passwords[uid].result
          }
        ],

        [
          for slot, file in lookup(var.assignment_files, team, {}) : {
            path        = "/var/lib/online-ide/upload/${basename(file.name)}"
            permissions = "0644"
            encoding    = "b64"
            content     = file.content_b64
          }
        ],

        # ip_mode = dual: die IPv4-Schnittstelle, die OpenTofu nach dem Boot
        # anhaengt. Ihre DHCP-Routen gehen in eine eigene Tabelle, und nur
        # Pakete mit ihrer Adresse als Absender nehmen diese Tabelle. Sonst
        # gingen Antworten ueber die Hauptschnittstelle hinaus, und Neutrons
        # Port-Security verwirft sie als gefaelschten Absender.
        local.dual ? [
          {
            path        = "/etc/netplan/60-secondary-ipv4.yaml"
            permissions = "0600"
            content = yamlencode({
              network = {
                version = 2
                ethernets = {
                  secondary = {
                    match           = { macaddress = local.secondary[team].mac }
                    dhcp4           = true
                    dhcp6           = false
                    accept-ra       = false
                    dhcp4-overrides = { route-table = 100 }
                    routing-policy  = [{ from = local.secondary[team].ipv4, table = 100 }]
                  }
                }
              }
            })
          },
        ] : [],
      )

      runcmd = concat(
        local.dual ? [
          # Die IPv4-Schnittstelle kommt erst nach dem Boot dazu. Bis zu
          # fuenf Minuten auf ihre MAC warten, dann die netplan-Datei oben
          # anwenden. Kommt sie nicht, bleibt die VM ueber IPv6 erreichbar.
          ["sh", "-c", "for i in $(seq 1 60); do if ip -o link | grep -qi \"$1\"; then netplan apply; break; fi; sleep 5; done", "sh", local.secondary[team].mac],
        ] : [],
        [
          # Als letzter Befehl: sein Exit-Code entscheidet, ob cloud-final
          # als fehlgeschlagen gilt.
          ["bash", "/opt/online-ide/online-ide-setup.sh"],
        ],
      )

      final_message = "Online-IDE fuer Team ${team} bereit"
    }
  }

  cloud_init = {
    for team, config in local.cloud_init_config : team => "#cloud-config\n${yamlencode(config)}"
  }
}
