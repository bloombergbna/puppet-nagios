# Class: nagios::client
#
# This is the main class to be included on all nodes to be monitored by nagios.
#
class nagios::client (
  $nagios_host_name                 = $facts['nagios_host_name'],
  $nagios_server                    = $facts['nagios_server'],
  # nrpe
  $nrpe_package                     = $nagios::params::nrpe_package,
  $nrpe_package_alias               = $nagios::params::nrpe_package_alias,
  $nrpe_cfg_file                    = $nagios::params::nrpe_cfg_file,
  $nrpe_service                     = $nagios::params::nrpe_service,
  $nrpe_cfg_dir                     = $nagios::params::nrpe_cfg_dir,
  # nrpe.cfg
  $nrpe_log_facility                = 'daemon',
  $nrpe_pid_file                    = $nagios::params::nrpe_pid_file,
  $nrpe_server_port                 = '5666',
  $nrpe_server_address              = undef,
  $nrpe_user                        = $nagios::params::nrpe_user,
  $nrpe_group                       = $nagios::params::nrpe_group,
  $nrpe_allowed_hosts               = '127.0.0.1',
  $nrpe_dont_blame_nrpe             = '0',
  $nrpe_command_prefix              = undef,
  $nrpe_debug                       = '0',
  $nrpe_command_timeout             = '60',
  $nrpe_connection_timeout          = '300',
  # host defaults
  $host_address                     = $facts['nagios_host_address'],
  $host_address6                    = $facts['nagios_host_address6'],
  $host_alias                       = $facts['nagios_host_alias'],
  $host_check_period                = $facts['nagios_host_check_period'],
  $host_check_command               = $facts['nagios_host_check_command'],
  $host_contact_groups              = $facts['nagios_host_contact_groups'],
  $host_hostgroups                  = $facts['nagios_host_hostgroups'],
  $host_notes                       = $facts['nagios_host_notes'],
  $host_notes_url                   = $facts['nagios_host_notes_url'],
  $host_notification_period         = $facts['nagios_host_notification_period'],
  $host_use                         = $facts['nagios_host_use'],
  # service defaults (hint: use host_* or override only service_use
  # for efficiently affecting all services or all instances of a service)
  $service_check_period             = $facts['nagios_service_check_period'],
  $service_contact_groups           = $facts['nagios_service_contact_groups'],
  $service_first_notification_delay = $facts['nagios_service_first_notification_delay'],
  $service_max_check_attempts       = $facts['nagios_service_max_check_attempts'],
  $service_notification_period      = $facts['nagios_service_notification_period'],
  $service_use                      = 'generic-service',
  # other
  $plugin_dir                       = $nagios::params::plugin_dir,
  $selinux                          = true,
  $defaultchecks                    = true,
) inherits ::nagios::params {

  # Set the variables to be used, including scoped from elsewhere, based on
  # the optional fact or parameter from here
  $host_name = $nagios_host_name ? {
    ''      => $facts['networking']['fqdn'],
    undef   => $facts['networking']['fqdn'],
    default => $nagios_host_name,
  }
  $server = $nagios_server ? {
    ''      => 'default',
    undef   => 'default',
    default => $nagios_server,
  }

  # Base package(s)
  # The 'nrpe' name is either inside $nrpe_package or is $nrpe_package_alias
  package { $nrpe_package:
    ensure => 'installed',
    alias  => $nrpe_package_alias,
  }

  # Most plugins use nrpe, so we install it everywhere
  service { $nrpe_service:
    ensure    => 'running',
    enable    => true,
    hasstatus => true,
    subscribe => File[$nrpe_cfg_file],
  }
  file { $nrpe_cfg_file:
    owner   => 'root',
    group   => $nrpe_group,
    mode    => '0640',
    content => template('nagios/nrpe.cfg.erb'),
    require => Package['nrpe']
  }
  # Included in the package, but we need to enable purging
  file { $nrpe_cfg_dir:
    ensure  => 'directory',
    owner   => 'root',
    group   => $nrpe_group,
    mode    => '0750',
    purge   => true,
    recurse => true,
    require => Package['nrpe'],
  }
  # Create resource for the check_* parent resource
  file { $plugin_dir:
    ensure  => 'directory',
    owner   => 'root',
    group   => 'root',
    mode    => '0775',
    require => Package['nrpe'],
  }

  # Don't assume directory exists
  if !defined(File['/etc/nagios']) {
    file { '/etc/nagios':
      ensure => 'directory',
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
  }

  # Where to store configuration for our custom nagios_* facts
  # These facts are mostly obsolete and pre-date hiera existence
  file { '/etc/nagios/facter':
    ensure  => 'directory',
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    purge   => true,
    recurse => true,
    require => Package['nrpe'],
  }

  # The initial fact, to be used to know if a node is a nagios client
  nagios::client::config { 'client': value => 'true' }

  # The main nagios_host entry
  nagios::host { $host_name:
    server              => $server,
    address             => $host_address,
    host_alias          => $host_alias,
    check_period        => $host_check_period,
    check_command       => $host_check_command,
    contact_groups      => $host_contact_groups,
    hostgroups          => $host_hostgroups,
    notes               => $host_notes,
    notes_url           => $host_notes_url,
    notification_period => $host_notification_period,
    use                 => $host_use,
  }

  # Enable all default checks by... default (can be disabled)
  # The check classes look up this scope's $service_* variables directly
  if $defaultchecks == true {
    # Always enabled ones (override $ensure to 'absent' to disable)
    class { '::nagios::check::conntrack': }
    class { '::nagios::check::cpu': }
    class { '::nagios::check::disk': }
    class { '::nagios::check::load': }
    class { '::nagios::check::ntp_time': }
    class { '::nagios::check::ping': }
    class { '::nagios::check::ping6': }
    class { '::nagios::check::ram': }
    class { '::nagios::check::swap': }
    # Conditional ones, once presence is detected using our custom facts
    if $facts['nagios_couchbase'] {        include nagios::check::couchbase }
    if $facts['nagios_pci_hpsa'] {         include nagios::check::hpsa }
    if $facts['nagios_httpd'] {            include nagios::check::httpd }
    if $facts['nagios_pci_megaraid_sas'] { include nagios::check::megaraid_sas }
    if $facts['nagios_memcached'] {        include nagios::check::memcached }
    if $facts['nagios_mongod'] {           include nagios::check::mongodb }
    if $facts['nagios_mountpoints'] {      include nagios::check::mountpoints }
    if $facts['nagios_moxi'] {             include nagios::check::moxi }
    if $facts['nagios_httpd_nginx'] {      include nagios::check::nginx }
    if $facts['nagios_pci_mptsas'] {       include nagios::check::mptsas }
    if $facts['nagios_mysqld'] {
      case $facts['os']['name'] {
        'RedHat', 'Fedora', 'CentOS', 'Scientific', 'Amazon': {
          include nagios::check::mysql_health
        }
        'Debian', 'Ubuntu': {
          # nagios-plugins-mysql_health doesn't exist for Trusty
          # https://launchpad.net/ubuntu/trusty/+search?text=nagios-plugins
        }
        default: {
          include nagios::check::mysql_health
        }
      }
    }
    if $facts['nagios_postgres'] {         include nagios::check::postgres }
  }

  # With selinux, some nrpe plugins require additional rules to work
  if $selinux and $facts['os']['selinux']['enforced'] {
    selinux::audit2allow { 'nrpe':
      source => "puppet:///modules/${module_name}/messages.nrpe",
    }
  }

}
