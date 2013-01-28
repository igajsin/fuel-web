class osnailyfacter::cluster_ha {

$controller_internal_addresses = parsejson($ctrl_management_addresses)
$controller_public_addresses = parsejson($ctrl_public_addresses)
$controller_hostnames = keys($controller_internal_addresses)
$galera_nodes = values($controller_internal_addresses)

$create_networks = true
if $network_manager == 'VlanManager' {
  $private_interface = $vlan_interface
}else{
  $private_interface = $fixed_interface
}
$network_config = {
  'vlan_start'     => $vlan_start,
}

$external_ipinfo = {}
$multi_host              = true
$quantum                 = false
$manage_volumes          = false
$cinder                  = false
$auto_assign_floating_ip = false
$glance_backend          = 'swift'

$network_manager = "nova.network.manager.${network_manager}"

$mysql_root_password     = 'nova'
$admin_email             = 'openstack@openstack.org'
$admin_password          = 'nova'
$keystone_db_password    = 'nova'
$keystone_admin_token    = 'nova'
$glance_db_password      = 'nova'
$glance_user_password    = 'nova'
$nova_db_password        = 'nova'
$nova_user_password      = 'nova'
$rabbit_password         = 'nova'
$rabbit_user             = 'nova'
$swift_shared_secret     = 'changeme'
$swift_user_password     = 'swift_pass'
$quantum_user_password   = 'quantum_pass' # Quantum is turned off
$quantum_db_password     = 'quantum_pass' # Quantum is turned off
$quantum_db_user         = 'quantum' # Quantum is turned off
$quantum_db_dbname       = 'quantum' # Quantum is turned off
$tenant_network_type     = 'gre' # Quantum is turned off
$quantum_host            = $management_vip # Quantum is turned off

$mirror_type = 'external'
$quantum_sql_connection  = "mysql://${quantum_db_user}:${quantum_db_password}@${quantum_host}/${quantum_db_dbname}" # Quantum is turned off
$controller_node_public  = $management_vip
$verbose = true
Exec { logoutput => true }

class compact_controller {
  class { 'openstack::controller_ha':
    controller_public_addresses   => $controller_public_addresses,
    controller_internal_addresses => $controller_internal_addresses,
    internal_address        => $internal_address,
    public_interface        => $public_interface,
    internal_interface      => $management_interface,
    private_interface       => $private_interface,
    internal_virtual_ip     => $management_vip,
    public_virtual_ip       => $public_vip,
    master_hostname         => $master_hostname,
    floating_range          => $floating_network_range,
    fixed_range             => $fixed_network_range,
    multi_host              => $multi_host,
    network_manager         => $network_manager,
    num_networks            => $num_networks,
    network_size            => $network_size,
    network_config          => $network_config,
    verbose                 => $verbose,
    auto_assign_floating_ip => $auto_assign_floating_ip,
    mysql_root_password     => $mysql_root_password,
    admin_email             => $admin_email,
    admin_password          => $admin_password,
    keystone_db_password    => $keystone_db_password,
    keystone_admin_token    => $keystone_admin_token,
    glance_db_password      => $glance_db_password,
    glance_user_password    => $glance_user_password,
    nova_db_password        => $nova_db_password,
    nova_user_password      => $nova_user_password,
    rabbit_password         => $rabbit_password,
    rabbit_user             => $rabbit_user,
    rabbit_nodes            => $controller_hostnames,
    memcached_servers       => $controller_hostnames,
    export_resources        => false,
    glance_backend          => $glance_backend,
    swift_proxies           => $controller_internal_addresses,
    quantum                 => $quantum,
    quantum_user_password   => $quantum_user_password,
    quantum_db_password     => $quantum_db_password,
    quantum_db_user         => $quantum_db_user,
    quantum_db_dbname       => $quantum_db_dbname,
    tenant_network_type     => $tenant_network_type,
    segment_range           => $segment_range,
    cinder                  => $cinder,
    manage_volumes          => $manage_volumes,
    galera_nodes            => $galera_nodes,
    mysql_skip_name_resolve => true,
    nv_physical_volume      => $nv_physical_volume,
  }
  class { 'swift::keystone::auth':
     password         => $swift_user_password,
     public_address   => $public_vip,
     internal_address => $management_vip,
     admin_address    => $management_vip,
  }
}


  case $role {
    "controller" : {
      include osnailyfacter::test_controller

      class { compact_controller: }
      class { 'openstack::swift::storage-node':
        storage_type => 'loopback',
        swift_zone => $uid,
        swift_local_net_ip => $internal_address,
      }
      class { 'openstack::swift::proxy':
        swift_proxies => $controller_internal_addresses,
        swift_master => $master_hostname,
        controller_node_address => $management_vip,
        swift_local_net_ip      => $internal_address,
      }
      if $hostname == $master_hostname {
        class { 'openstack::img::cirros':
          os_password => $admin_password,
          os_auth_url => "http://${management_vip}:5000/v2.0/",
          img_name    => "TestVM",
        }
        Class[glance::api]                    -> Class[openstack::img::cirros]
        Class[openstack::swift::storage-node] -> Class[openstack::img::cirros]
        Class[openstack::swift::proxy]        -> Class[openstack::img::cirros]
        Service[swift-proxy]                  -> Class[openstack::img::cirros]
      }

      Class[osnailyfacter::network_setup]   -> Class[openstack::controller_ha]
      Class[osnailyfacter::network_setup]   -> Class[openstack::swift::storage-node]
      Class[osnailyfacter::network_setup]   -> Class[openstack::swift::proxy]
    }

    "compute" : {
      include osnailyfacter::test_compute

      class { 'openstack::compute':
        public_interface       => $public_interface,
        private_interface      => $private_interface,
        internal_address       => $internal_address,
        libvirt_type           => 'qemu',
        fixed_range            => $fixed_network_range,
        network_manager        => $network_manager,
        network_config         => $network_config,
        multi_host             => $multi_host,
        sql_connection         => "mysql://nova:${nova_db_password}@${management_vip}/nova",
        rabbit_nodes           => $controller_hostnames,
        rabbit_password        => $rabbit_password,
        rabbit_user            => $rabbit_user,
        glance_api_servers     => "${management_vip}:9292",
        vncproxy_host          => $public_vip,
        verbose                => $verbose,
        vnc_enabled            => true,
        manage_volumes         => false,
        nova_user_password     => $nova_user_password,
        cache_server_ip        => $controller_hostnames,
        service_endpoint       => $management_vip,
        quantum                => $quantum,
        quantum_host           => $quantum_host,
        quantum_sql_connection => $quantum_sql_connection,
        quantum_user_password  => $quantum_user_password,
        tenant_network_type    => $tenant_network_type,
        segment_range          => $segment_range,
        cinder                 => $cinder,
        db_host                => $internal_virtual_ip,
      }

      Class[osnailyfacter::network_setup] -> Class[openstack::compute]
    }
  }
}
