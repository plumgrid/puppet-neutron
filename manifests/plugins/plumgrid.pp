# Configure the neutron server to use the plumgrid plugin.
# === Parameters
#
class neutron::plugins::plumgrid (
  $package_ensure               = 'installed',
  $pg_connection                = undef,
  $pg_director_server           = undef,
  $pg_director_server_port      = undef,
  $pg_username                  = undef,
  $pg_password                  = undef,
  $pg_servertimeout             = undef,
  $pg_enable_metadata_agent     = false,
  $admin_password               = undef,
  $controller_priv_host         = undef,
  $auth_protocol                = 'http',
  $nova_metadata_ip             = '127.0.0.1',
  $nova_metadata_port           = '8775',
  $metadata_proxy_shared_secret = undef,
) {

  include neutron::params

  Package['neutron'] -> Package[$::neutron::params::plumgrid_plugin_package]
  Package[$::neutron::params::plumgrid_plugin_package] -> Neutron_plugin_plumgrid<||>
  Neutron_plugin_plumgrid<||> ~> Service<| title == 'neutron-server' |>
  Package[$::neutron::params::plumgrid_plugin_package] ~> Service<| title == 'neutron-server' |>
  Package[$::neutron::params::plumgrid_plugin_package] -> Package[$::neutron::params::plumgrid_pythonlib_package]
  Package[$::neutron::params::plumgrid_pythonlib_package] -> Neutron_plumlib_plumgrid<||>
  Neutron_plumlib_plumgrid<||> ~> Service<| title == 'neutron-server' |>
  Neutron_plumlib_plumgrid<||> -> Exec['sync-default-sec-grp']

  if $::osfamily == 'Debian' {
    file_line { '/etc/default/neutron-server:NEUTRON_PLUGIN_CONFIG':
      path    => '/etc/default/neutron-server',
      match   => '^NEUTRON_PLUGIN_CONFIG=(.*)$',
      line    => "NEUTRON_PLUGIN_CONFIG=${::neutron::params::plumgrid_config_file}",
      require => [ Package['neutron-server'], Package[$::neutron::params::plumgrid_plugin_package] ],
      notify  => Service['neutron-server'],
    }
  }

  package { '$::neutron::params::plumgrid_plugin_package':
    ensure  => $package_ensure,
    name    => $::neutron::params::plumgrid_plugin_package,
    configfiles => replace,
  }

  package { '$::neutron::params::plumgrid_pythonlib_package':
    ensure  => $package_ensure,
    name    => $::neutron::params::plumgrid_pythonlib_package,
    configfiles => replace,
  }

  package { '$::neutron::params::python_retrying_package':
    ensure  => $package_ensure,
    name    => $::neutron::params::python_retrying_package,
  }

  exec { 'sync-default-sec-grp':
    command     => 'neutron security-group-delete default',
    path        => '/usr/bin',
    refreshonly => true,
  }

  if $::osfamily == 'Debian' {
    $plumgrid_plugin_path = '/usr/share/pyshared/neutron/plugins/plumgrid'
  } elsif $::osfamily == 'Redhat' {
    if $::operatingsystemmajrelease >= 7 {
      $plumgrid_plugin_path = '/usr/lib/python2.7/site-packages/neutron/plugins/plumgrid'
    } 
    else {
      $plumgrid_plugin_path = '/usr/lib/python2.6/site-packages/neutron/plugins/plumgrid'
    }
  }
  else {
    warning('Unknown operating system, skipping PLUMgrid plugin patch')
  }

  file { $plumgrid_plugin_path:
    source  => "puppet:///modules/neutron/plumgrid",
    ensure  => directory,
    recurse => true,
    purge   => true,
    backup  => false,
    notify  => Service[$::neutron::params::server_service],
    require => [Package[$::neutron::params::plumgrid_plugin_package], Package[$::neutron::params::plumgrid_pythonlib_package], Package[$::neutron::params::python_retrying_package] ],
  }

  neutron_plugin_plumgrid {
    'PLUMgridDirector/director_server': value => $pg_director_server;
    'PLUMgridDirector/director_server_port' : value => $pg_director_server_port;
    'PLUMgridDirector/username': value => $pg_username;
    'PLUMgridDirector/password': value => $pg_password;
    'PLUMgridDirector/servertimeout': value => $pg_servertimeout;
    'database/connection': value => $pg_connection;
  }
  neutron_plumlib_plumgrid {
    'keystone_authtoken/admin_user' : value => 'admin';
    'keystone_authtoken/admin_password': value => $admin_password;
    'keystone_authtoken/auth_uri': value => "${auth_protocol}://$controller_priv_host:35357/v2.0";
    'keystone_authtoken/admin_tenant_name': value => 'admin';
    'PLUMgridLibrary/vapp_flag': value => 'True';
    'PLUMgridLibrary/enable_pg_security': value => 'True';
    'PLUMgridMetadata/nova_metadata_ip': value => "$nova_metadata_ip";
    'PLUMgridMetadata/nova_metadata_port': value => "$nova_metadata_port";
    'PLUMgridMetadata/metadata_proxy_shared_secret': value => "$metadata_proxy_shared_secret";
  }

  if $::osfamily == 'Redhat' {
    file {'/etc/neutron/plugin.ini':
      ensure  => link,
      target  => '/etc/neutron/plugins/plumgrid/plumgrid.ini',
      require => Package['openstack-neutron-plumgrid'],
    }
  }

  if $pg_enable_metadata_agent {
    file { [ "/etc/neutron/rootwrap.d" ]:
          ensure => directory,
    }

    file {'/etc/neutron/rootwrap.d/plumlib.filters':
      owner => root,
      group => root,
      mode => 0600,
      content => template('neutron/plumlib.filters.erb'),
      require => File['/etc/neutron/rootwrap.d'],
    }

    neutron_plumlib_plumgrid {
    'PLUMgridMetadata/enable_pg_metadata' :   value => 'True';
    'PLUMgridMetadata/metadata_mode':         value => 'local';
    }

    file_line { $::neutron::params::neutron_sudoers_file :
      path    => $::neutron::params::neutron_sudoers_file,
      ensure  => present,
      line    => "neutron ALL = (ALL) NOPASSWD:ALL",
      require => Package[$::neutron::params::package_name],
      notify  => Service[$::neutron::params::server_service],
    }
  }
  else {
    neutron_plumlib_plumgrid {
    'PLUMgridMetadata/enable_pg_metadata' :   value => 'False';
    }
  }
}
