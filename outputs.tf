output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "vm_private_ips" {
  description = "IPs privadas (no hay IPs públicas)"
  value       = module.compute.private_ips
}

output "test_ping_vm1_to_vm2" {
  description = "Comando para probar el ping interno"
  value       = "az vm run-command invoke -g ${azurerm_resource_group.this.name} -n ${var.prefix}-vm1 --command-id RunShellScript --scripts \"ping -c 4 ${module.compute.private_ips["vm2"]}\" --query \"value[0].message\" -o tsv"
}