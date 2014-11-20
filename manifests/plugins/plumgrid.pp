# Configure the neutron server to use the plumgrid plugin.
# === Parameters
#
class neutron::plugins::plumgrid (
  $package_ensure           = 'installed',
  $pg_connection            = undef,
  $pg_director_server       = undef,
  $pg_director_server_port  = undef,
  $pg_username              = undef,
  $pg_password              = undef,
  $pg_servertimeout         = undef,
  $pg_enable_metadata_agent = false,
  $admin_password           = undef,
  $metadata_proxy_secret    = undef,
  $controller_priv_host     = undef,
) {

  include neutron::params

  Package['neutron'] -> Package[$::neutron::params::plumgrid_plugin_package]
  Package[$::neutron::params::plumgrid_plugin_package] -> Neutron_plugin_plumgrid<||>
  Neutron_plugin_plumgrid<||> ~> Service<| title == 'neutron-server' |>
  Package[$::neutron::params::plumgrid_plugin_package] -> File['remove plumgrid.ini']
  File['remove plumgrid.ini'] -> Service<| title == 'neutron-server' |>
  Package[$::neutron::params::plumgrid_plugin_package] -> Package[$::neutron::params::plumgrid_pythonlib_package]
  Package[$::neutron::params::plumgrid_pythonlib_package] -> Neutron_plumlib_plumgrid<||>
  Neutron_plumlib_plumgrid<||> ~> Service<| title == 'neutron-server' |>

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

  file { 'remove plumgrid.ini':
      path => '/etc/neutron/plugins/plumgrid/plumgrid.ini',
      ensure => absent,
      require => [Package[$::neutron::params::plumgrid_plugin_package] ],
  }

   if $::osfamily == 'Debian' {
      $plumlib_path = '/usr/share/pyshared/neutron/plugins/plumgrid/drivers/plumlib.py'
      $plumgrid_plugin_path = '/usr/share/pyshared/neutron/plugins/plumgrid/plumgrid_plugin/plumgrid_plugin.py' 
   } elsif $::osfamily == 'Redhat' {
      if $::operatingsystemmajrelease >= 7 {
        $plumlib_path = '/usr/lib/python2.7/site-packages/neutron/plugins/plumgrid/drivers/plumlib.py'
        $plumgrid_plugin_path = '/usr/lib/python2.7/site-packages/neutron/plugins/plumgrid/plumgrid_plugin/plumgrid_plugin.py'
      } 
      else {
        $plumlib_path = '/usr/lib/python2.6/site-packages/neutron/plugins/plumgrid/drivers/plumlib.py'
        $plumgrid_plugin_path = '/usr/lib/python2.6/site-packages/neutron/plugins/plumgrid/plumgrid_plugin/plumgrid_plugin.py'
      }
   }
   else {
      warning('Unknown operating system, skipping PLUMgrid plugin patch')
   }

  file { $plumlib_path:
    ensure => file,
    content => template('neutron/plumlib.py.erb'),
    require => [Package[$::neutron::params::plumgrid_plugin_package], Package[$::neutron::params::plumgrid_pythonlib_package] ],
  }

  file { $plumgrid_plugin_path:
    ensure => file,
    content => template('neutron/plumgrid_plugin.py.erb'),
    require => [Package[$::neutron::params::plumgrid_plugin_package], Package[$::neutron::params::plumgrid_pythonlib_package] ],
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
    'PLUMgridKeystone/os_username' : value => 'admin';
    'PLUMgridKeystone/os_password': value => $admin_password;
    'PLUMgridKeystone/os_auth_url': value => 'http://${controller_priv_host}:35357/v2.0';
    'PLUMgridKeystone/os_tenant_name': value => 'admin';
  }

  if $::osfamily == 'Redhat' {
    file {'/etc/neutron/plugin.ini':
      ensure  => link,
      target  => '/etc/neutron/plugins/plumgrid/plumgrid.ini',
      require => Package['openstack-neutron-plumgrid'],
    }
  }

  if $pg_enable_metadata_agent {
    if $::operatingsystem == 'CentOS' {
      $auth_region = 'openstack'
    }
    else {
      $auth_region = 'RegionOne'
    }

    class { '::neutron::agents::metadata' :
      auth_password => $admin_password,
      shared_secret => $metadata_proxy_secret,
      auth_tenant   => 'admin',
      auth_user     => 'admin',
      auth_region   => $auth_region,
    }

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
