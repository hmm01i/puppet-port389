# port389::instance
define port389::instance (
  $admin_domain               = $::port389::admin_domain,
  $config_directory_admin_id  = $::port389::config_directory_admin_id,
  $config_directory_admin_pwd = $::port389::config_directory_admin_pwd,
  $config_directory_ldap_url  = $::port389::config_directory_ldap_url,
  $root_dn                    = $::port389::root_dn,
  $root_dn_pwd                = $::port389::root_dn_pwd,
  $server_port                = $::port389::server_port,
  $enable_ssl                 = $::port389::enable_ssl,
  $ssl_server_port            = $::port389::ssl_server_port,
  $ssl_cert                   = $::port389::ssl_cert,
  $ssl_key                    = $::port389::ssl_key,
  $ssl_ca_certs               = $::port389::ssl_ca_certs,
  $schema_file                = undef,
  $suffix                     = port389_domain2dn($::port389::admin_domain),
  $disable_selinux_config     = false,
  $disable_systemd_config     = false,
  $install_admin_server       = true,
  $start_server               = 'yes',
) {
  # follow the same server identifier validation rules as setup-ds-admin.pl/setup-ds.pl
  validate_re($title, '^[\w#%:@-]*$', "The ServerIdentifier '${title}' contains invalid characters.  It must contain only alphanumeric characters and the following: #%:@_-")
  validate_string($admin_domain)
  validate_string($config_directory_admin_id)
  validate_string($config_directory_admin_pwd)
  validate_string($config_directory_ldap_url)
  validate_string($root_dn)
  validate_string($root_dn_pwd)
  validate_string($server_port)
  # ssl
  validate_bool($enable_ssl)
  # don't validate ssl_* params unless $enable_ssl == true
  if $enable_ssl {
    validate_string($ssl_server_port)
    validate_absolute_path($ssl_cert)
    validate_absolute_path($ssl_key)
    validate_hash($ssl_ca_certs)
  }
  # schema_file may be undef
  validate_string($suffix)

  if $install_admin_server {
    $install_script = "setup-ds-admin.pl" 
  } else {
    $install_script = "setup-ds.pl"
  }

  $setup_inf_name = "setup_${title}.inf"
  $setup_inf_path = "${::port389::setup_dir}/${setup_inf_name}"

  # per
  # https://access.redhat.com/site/documentation/en-US/Red_Hat_Directory_Server/9.0/html/Installation_Guide/Advanced_Configuration-Silent.html

  $data = {
    'General' => {
      'AdminDomain'             => $admin_domain,
      'ConfigDirectoryAdminID'  => $config_directory_admin_id,
      'ConfigDirectoryAdminPwd' => $config_directory_admin_pwd,
      'ConfigDirectoryLdapURL'  => $config_directory_ldap_url,
      'FullMachineName'         => $::port389::full_machine_name,
      'ServerRoot'              => '/usr/lib64/dirsrv',
      'SuiteSpotGroup'          => $::port389::group,
      'SuiteSpotUserID'         => $::port389::user,
    },
    'admin'   => {
      'Port'            => $::port389::server_admin_port,
      'ServerAdminID'   => $::port389::server_admin_id,
      'ServerAdminPwd'  => $::port389::server_admin_pwd,
      'ServerIpAddress' => $::port389::server_ipaddress,
      'SysUser'         => $::port389::user,
    },
    'slapd'   => {
      'AddOrgEntries'    => 'No',
      'AddSampleEntries' => 'No',
      'InstallLdifFile'  => '',
      'RootDN'           => $root_dn,
      'RootDNPwd'        => $root_dn_pwd,
      'SchemaFile'       => $schema_file,
      'ServerIdentifier' => $title,
      'ServerPort'       => $server_port,
      'SlapdConfigForMC' => 'yes',
      'Suffix'           => $suffix,
      'UseExistingMC'    => '0',
      'ds_bename'        => 'userRoot',
      'start_server'     => $start_server, 
      #'bak_dir' => '/var/lib/dirsrv/slapd-ldap1/bak',
      #'bindir' => '/usr/bin',
      #'cert_dir' => '/etc/dirsrv/slapd-ldap1',
      #'config_dir' => '/etc/dirsrv/slapd-ldap1',
      #'datadir' => '/usr/share',
      #'db_dir' => '/var/lib/dirsrv/slapd-ldap1/db',
      #'ds_bename' => 'userRoot',
      #'inst_dir' => '/usr/lib64/dirsrv/slapd-ldap1',
      #'ldif_dir' => '/var/lib/dirsrv/slapd-ldap1/ldif',
      #'localstatedir' => '/var',
      #'lock_dir' => '/var/lock/dirsrv/slapd-ldap1',
      #'log_dir' => '/var/log/dirsrv/slapd-ldap1',
      #'naming_value' => 'stage',
      #'run_dir' => '/var/run/dirsrv',
      #'sbindir' => '/usr/sbin',
      #'schema_dir' => '/etc/dirsrv/slapd-ldap1/schema',
      #'sysconfdir' => '/etc',
      #'tmp_dir' => '/tmp',
    },
  }
  if versioncmp($::operatingsystemrelease,'7.0') < 0 {
    $servicename = $title
  } else {
    $servicename = "dirsrv@${title}"
  }
  

  
  case $::port389::ensure {
    'present', 'latest': {
      # disable bucketting since the .inf file contains password information
      file { $setup_inf_name:
        ensure  => file,
        path    => $setup_inf_path,
        owner   => $::port389::user,
        group   => $::port389::group,
        mode    => '0600',
        content => template("${module_name}/inf.erb"),
        backup  => false,
      } ->
      # /usr/sbin/setup-ds-admin.pl needs:
      #   /bin/{grep, cat, uname, sleep, ...}
      #   /sbin/service
      #   /usr/bin/env
      exec { "${install_script}_${title}":
        path      => [ '/bin', '/sbin', '/usr/bin', '/usr/sbin' ],
        command   => "${install_script} --file=${setup_inf_path} --silent -ddddd",
        unless    => "/usr/bin/test -e /etc/dirsrv/slapd-${title}",
        logoutput => true,
        notify    => Service[ $servicename ],
      }
      
      notify {"Disable selinux config is $disable_selinux_config": }
      if $disable_selinux_config {
        notify {"Running sed exec": } ->
        exec { "disable selinux with sed":
          path      => [ '/bin', '/sbin', '/usr/bin', '/usr/sbin' ],
          command   => "sed -i 's/sub updateSelinuxPolicy {/& return;/' /usr/lib64/dirsrv/perl/*.pm",
          unless    => 'grep "sub updateSelinuxPolicy { return; /usr/lib64/dirsrv/perl/*.pm' ,
          logoutput => true,
          before    => Exec["${install_script}_${title}"],
          require   => Package['389-ds-base'],
        } ->
        notify {"Ran sed exec": }
      }

      notify {"Disable systemd config is $disable_systemd_config": }
      if $disable_systemd_config {
        notify {"Running sed exec systemd": } ->
        exec { "disable systemd with sed":
          path      => [ '/bin', '/sbin', '/usr/bin', '/usr/sbin' ],
          command   => "sed -i 's/sub updateSystemD {/& return;/' /usr/lib64/dirsrv/perl/*.pm",
          unless    => 'grep "sub updateSystemD { return; /usr/lib64/dirsrv/perl/*.pm' ,
          logoutput => true,
          before    => Exec["${install_script}_${title}"],
          require   => Package['389-ds-base'],
        } ->
        notify {"Ran sed exec systemd": }
      }
      


      if $enable_ssl {
        Exec["${install_script}_${title}"] ->
        port389::instance::ssl { $name:
          root_dn         => $root_dn,
          root_dn_pwd     => $root_dn_pwd,
          server_port     => $server_port,
          ssl_server_port => $ssl_server_port,
          ssl_cert        => $ssl_cert,
          ssl_key         => $ssl_key,
          ssl_ca_certs    => $ssl_ca_certs,
          notify          => Service[ $servicename],
        }
      }
      if $install_admin_server {
        include port389::admin::service
  
        Exec["${install_script}_${title}"] ->
        Class['port389::admin::service']
  
        if $::port389::enable_server_admin_ssl {
          include port389::admin::ssl

          Exec["${install_script}_${title}"] ->
          Class['port389::admin::ssl'] ->
          Class['port389::admin::service']
        }
      }

      if versioncmp($::operatingsystemrelease,'7.0') < 0 { 
        # XXX this is extremely RedHat specific
        service { $title :
          ensure     => 'running',
          control    => 'dirsrv',
          hasstatus  => true,
          hasrestart => true,
          provider   => 'redhat_instance',
        }
      } else {
        service { $servicename :
          ensure     => 'running',
          hasstatus  => true,
          hasrestart => true,
         } 
      }
    }
    default: {
      warning("it is meaningless to declare Port389::Instance[${name}] while Class[port389]{ ensure => 'absent|purged' }")
    }
  }
}
