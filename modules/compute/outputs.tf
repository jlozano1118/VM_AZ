output "private_ips" {
  value = { for k, nic in azurerm_network_interface.this : k => nic.private_ip_address }
}

output "vm_ids" {
  value = { for k, vm in azurerm_linux_virtual_machine.this : k => vm.id }
}