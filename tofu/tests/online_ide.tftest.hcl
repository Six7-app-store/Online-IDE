# Prüft, wie Team-VMs, Ports, Zugangsdaten und Einrichtung aus den Variablen
# entstehen. Alle Provider sind gemockt: der Test braucht keinen
# OpenStack-Zugang und legt nichts an.
#
#   cd tofu && tofu init -backend=false && tofu test

mock_provider "openstack" {
  mock_data "openstack_images_image_v2" {
    defaults = {
      id = "00000000-0000-0000-0000-00000000image"
    }
  }
  mock_resource "openstack_networking_port_v2" {
    defaults = {
      all_fixed_ips = ["141.72.10.7", "2001:db8:4::7"]
      mac_address   = "fa:16:3e:00:00:07"
    }
  }
}

mock_provider "random" {}

variables {
  users = {
    "Team #1" = [{ email = "Anna.Alt@dhbw.de" }, { email = "1ben@dhbw.de" }]
    "b"       = [{ email = "cem@dhbw.de" }]
  }
}

run "eine_vm_je_team_und_ein_port_je_person" {
  command = apply

  assert {
    condition     = length(openstack_compute_instance_v2.team_vm) == 2
    error_message = "Jedes Team braucht genau eine VM."
  }
  assert {
    condition     = openstack_compute_instance_v2.team_vm["Team #1"].name == "online-ide-team-1"
    error_message = "Der VM-Name muss ein gueltiger Hostname sein (\"Team #1\" -> team-1)."
  }
  assert {
    condition     = output.user_accounts["Team #1-1ben"].port == 8080 && output.user_accounts["Team #1-Anna-Alt"].port == 8081
    error_message = "Jede Person im Team bekommt ihren eigenen Port ab 8080."
  }
  assert {
    condition     = output.user_accounts["b-cem"].port == 8080
    error_message = "Die Ports zaehlen je Team-VM neu ab 8080."
  }
  assert {
    condition     = output.user_accounts["Team #1-1ben"].username == "u1ben"
    error_message = "Linux-Namen muessen mit einem Buchstaben beginnen."
  }
}

run "einrichtung_je_team" {
  command = apply

  assert {
    condition     = startswith(local.cloud_init["b"], "#cloud-config\n")
    error_message = "user_data muss mit #cloud-config beginnen."
  }
  assert {
    condition     = [for u in yamldecode(local.cloud_init["Team #1"]).users : u.name] == ["u1ben", "annaalt"]
    error_message = "Auf der VM eines Teams entstehen genau die Konten seiner Mitglieder."
  }
  assert {
    condition     = one([for f in yamldecode(local.cloud_init["Team #1"]).write_files : f.content if f.path == "/etc/online-ide/users"]) == "u1ben 8080\nannaalt 8081\n"
    error_message = "Das Setup-Skript braucht Nutzer und Port je Zeile."
  }
  assert {
    condition     = length([for f in yamldecode(local.cloud_init["b"]).write_files : f if startswith(f.path, "/opt/online-ide/aufgaben/")]) == 10
    error_message = "Die zehn Standard-Aufgaben muessen auf der VM liegen."
  }
  assert {
    condition     = yamldecode(local.cloud_init["b"]).runcmd[length(yamldecode(local.cloud_init["b"]).runcmd) - 1] == ["bash", "/opt/online-ide/online-ide-setup.sh"]
    error_message = "Das Setup-Skript muss zuletzt laufen, sein Exit-Code entscheidet ueber cloud-final."
  }
}

run "aufgabe_nur_fuer_ihr_team" {
  command = apply

  variables {
    assignment_files = {
      "b" = {
        uploaded = {
          name         = "blatt1.zip"
          content_b64  = "UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA=="
          content_type = "application/zip"
          size         = 22
        }
      }
    }
  }

  assert {
    condition     = contains([for f in yamldecode(local.cloud_init["b"]).write_files : f.path], "/var/lib/online-ide/upload/blatt1.zip")
    error_message = "Die ZIP des Teams muss auf seiner VM landen."
  }
  assert {
    condition     = length([for f in yamldecode(local.cloud_init["Team #1"]).write_files : f if startswith(f.path, "/var/lib/online-ide/upload/")]) == 0
    error_message = "Ein anderes Team darf die ZIP nicht bekommen."
  }
}

run "zugang_ueber_ipv6" {
  command = apply

  assert {
    condition     = alltrue([for a in values(output.user_accounts) : a.ip == "2001:db8:4::7" && a.protocol == "web"])
    error_message = "Im Standardnetz ist nur IPv6 oeffentlich - die Zugangsdaten muessen sie nennen."
  }
  assert {
    condition     = output.team_vms["b"].users[0].ide_url == "http://[2001:db8:4::7]:8080/"
    error_message = "Eine IPv6-Adresse gehoert in der URL in eckige Klammern."
  }
  assert {
    condition     = keys(openstack_networking_secgroup_rule_v2.ide) == ["IPv6"]
    error_message = "Ohne Auswahl gilt ipv6: nur eine Regel fuer IPv6."
  }
  assert {
    condition     = openstack_networking_secgroup_rule_v2.ide["IPv6"].port_range_min == 8080 && openstack_networking_secgroup_rule_v2.ide["IPv6"].port_range_max == 8099
    error_message = "Die Regel muss den ganzen Portblock der IDEs oeffnen."
  }
}

run "ipv4_nur_aus_dem_campus" {
  command = apply

  variables {
    ip_mode         = "ipv4"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = openstack_networking_secgroup_rule_v2.ide["IPv4"].remote_ip_prefix == "141.72.0.0/16"
    error_message = "Ueber IPv4 bleibt die IDE auf Campus und VPN beschraenkt."
  }
  assert {
    condition     = output.team_vms["b"].url == "http://141.72.10.7:8080/"
    error_message = "Die URL muss die IPv4 der VM nennen."
  }
}

run "dual_haengt_ipv4_als_zweite_schnittstelle_an" {
  command = apply

  variables {
    ip_mode         = "dual"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = length(openstack_compute_interface_attach_v2.team_v4) == 2
    error_message = "dual braucht je Team-VM eine IPv4-Schnittstelle als zweiten Port."
  }
  assert {
    condition     = toset(keys(openstack_networking_secgroup_rule_v2.ide)) == toset(["IPv4", "IPv6"])
    error_message = "dual braucht Regeln fuer beide Familien."
  }
}

run "zu_grosses_team_wird_abgelehnt" {
  command = plan

  variables {
    users = {
      "gross" = [for i in range(21) : { email = "person${i}@dhbw.de" }]
    }
  }

  expect_failures = [terraform_data.limits]
}

run "zu_viele_teams_werden_abgelehnt" {
  command = plan

  variables {
    max_teams = 1
  }

  expect_failures = [terraform_data.limits]
}

run "unbekannter_flavor_wird_abgelehnt" {
  command = plan

  variables {
    flavor = "gpu.huge"
  }

  expect_failures = [var.flavor]
}
