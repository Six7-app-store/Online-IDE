############################
# [CONTRACT] User Accounts Output
############################

# Schluessel "<team>-<lokaler Teil der E-Mail>", wie vom App Store fuer die
# Zuordnung zu den Mitgliedern verlangt. Aus ip und port baut die Oberflaeche
# den Link zur eigenen IDE.
output "user_accounts" {
  description = "[CONTRACT] User accounts mit Login-Informationen"
  sensitive   = true
  value = {
    for uid, user in local.users_map : uid => {
      type     = "password"
      protocol = "web"
      ip       = local.team_ip[user.team]
      port     = local.user_ports[uid]
      username = user.username
      auth     = random_password.user_passwords[uid].result
      email    = user.email
      team     = user.team
    }
  }
}

############################
# Team-VM Details
############################

output "team_vms" {
  description = "Details aller Team-VMs"
  value = {
    for team in local.teams_list : team => {
      instance_id   = openstack_compute_instance_v2.team_vm[team].id
      instance_name = openstack_compute_instance_v2.team_vm[team].name
      ip_mode       = var.ip_mode
      fixed_ip_v4   = local.team_ipv4[team]
      fixed_ip_v6   = local.team_ipv6[team]
      url           = "http://${local.team_host[team]}:${local.first_port}/"
      users = [
        for uid in local.team_members[team] : {
          username = local.users_map[uid].username
          ide_url  = "http://${local.team_host[team]}:${local.user_ports[uid]}/"
        }
      ]
    }
  }
}

output "teams_summary" {
  description = "Übersicht: Teams und User-Anzahl"
  value = {
    for team in local.teams_list : team => length(local.team_members[team])
  }
}
