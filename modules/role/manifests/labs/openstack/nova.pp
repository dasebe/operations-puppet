class role::labs::openstack::nova::common {

    include passwords::misc::scripts
    include role::labs::openstack::nova::wikiupdates

    $novaconfig_pre                       = hiera_hash('novaconfig', {})
    $keystoneconfig                       = hiera_hash('keystoneconfig', {})

    $keystone_host                        = hiera('labs_keystone_host')
    $nova_controller                      = hiera('labs_nova_controller')
    $nova_api_host                        = hiera('labs_nova_api_host')
    $network_host                         = hiera('labs_nova_network_host')
    $status_wiki_host_master              = hiera('status_wiki_host_master')

    $extra_novaconfig = {
        bind_ip                => ipresolve($keystone_host,4),
        keystone_auth_host     => $keystoneconfig['auth_host'],
        keystone_auth_port     => $keystoneconfig['auth_port'],
        keystone_admin_token   => $keystoneconfig['admin_token'],
        keystone_auth_protocol => $keystoneconfig['auth_protocol'],
        auth_uri               => "http://${nova_controller}:5000",
        api_ip                 => ipresolve($nova_api_host,4),
        controller_address     => ipresolve($nova_controller,4),
    }
    $novaconfig = deep_merge($novaconfig_pre, $extra_novaconfig)

    class { '::openstack::common':
        novaconfig                       => $novaconfig,
        instance_status_wiki_host        => $status_wiki_host_master,
        instance_status_wiki_domain      => 'labs',
        instance_status_wiki_page_prefix => 'Nova_Resource:',
        instance_status_wiki_region      => $::site,
        instance_status_dns_domain       => "${::site}.wmflabs",
        instance_status_wiki_user        => $passwords::misc::scripts::wikinotifier_user,
        instance_status_wiki_pass        => $passwords::misc::scripts::wikinotifier_pass,
    }
}

# This is the wikitech UI
class role::labs::openstack::nova::manager {
    system::role { $name: }
    include ::nutcracker::monitoring
    include ::mediawiki::packages::php5
    include ::mediawiki::packages::math
    include ::mediawiki::packages::tex
    include ::mediawiki::cgroup
    include ::scap::scripts

    include role::labs::openstack::nova::common
    $novaconfig = $role::labs::openstack::nova::common::novaconfig

    case $::realm {
        'production': {
            $sitename = 'wikitech.wikimedia.org'
            $certificate = $sitename
            sslcert::certificate { $sitename: }
        }
        'labtest': {
            $sitename = 'labtestwikitech.wikimedia.org'
            $certificate = 'labtestwikitech'
            letsencrypt::cert::integrated { $certificate:
                subjects   => $sitename,
                puppet_svc => 'apache2',
                system_svc => 'apache2',
            }
        }
        default: {
            notify {"unknown realm ${::realm}; https cert will not be installed.":}
        }
    }

    monitoring::service { 'https':
        description   => 'HTTPS',
        check_command => "check_ssl_http!${sitename}",
    }

    $ssl_settings = ssl_ciphersuite('apache', 'compat', true)

    ferm::service { 'wikitech_http':
        proto => 'tcp',
        port  => '80',
    }

    ferm::service { 'wikitech_https':
        proto => 'tcp',
        port  => '443',
    }

    ferm::service { 'deployment-ssh':
        proto  => 'tcp',
        port   => '22',
        srange => '$DEPLOYMENT_HOSTS',
    }

    # allow keystone to query the wikitech db
    $keystone_host = hiera('labs_keystone_host')
    ferm::service { 'mysql_keystone':
        proto  => 'tcp',
        port   => '3306',
        srange => "@resolve(${keystone_host})",
    }

    class { '::openstack::openstack_manager':
        novaconfig         => $novaconfig,
        webserver_hostname => $sitename,
        certificate        => $certificate,
    }

    # T89323
    monitoring::service { 'wikitech-static-sync':
        description   => 'are wikitech and wt-static in sync',
        check_command => 'check_wikitech_static',
    }

    # For Math extensions file (T126628)
    file { '/srv/math-images':
        ensure => 'directory',
        owner  => 'www-data',
        group  => 'www-data',
        mode   => '0755',
    }

    # On app servers and image scalers, convert(1) from imagemagick is
    # contained in a firejail profile. Silver receives the same setting
    # in wmf-config/CommonSettings.php via $wgImageMagickConvertCommand
    # and since we also need to scale graphics on wikitech, provide them here
    file { '/usr/local/bin/mediawiki-firejail-convert':
        source => 'puppet:///modules/mediawiki/mediawiki-firejail-convert',
        owner  => 'root',
        group  => 'root',
        mode   => '0555',
    }

    file { '/etc/firejail/mediawiki-converters.profile':
        source => 'puppet:///modules/mediawiki/mediawiki-converters.profile',
        owner  => 'root',
        group  => 'root',
        mode   => '0644',
    }

    class { '::nutcracker':
        mbuf_size => '64k',
        verbosity => 2,
        pools     => {
            'memcached' => {
                distribution       => 'ketama',
                hash               => 'md5',
                listen             => '127.0.0.1:11212',
                server_connections => 2,
                servers            => [
                    '127.0.0.1:11000:1',
                ],
            },
        },
    }
}

# This is nova controller stuff
class role::labs::openstack::nova::controller {
    system::role { $name: }

    require openstack
    include role::labs::openstack::nova::wikiupdates
    include role::labs::openstack::glance::server
    include role::labs::openstack::keystone::server
    include ::openstack::nova::conductor
    include ::openstack::nova::spiceproxy
    include ::openstack::nova::scheduler
    include role::labs::openstack::nova::common
    $novaconfig = $role::labs::openstack::nova::common::novaconfig
    $designateconfig = hiera_hash('designateconfig', {})

    class { '::openstack::queue_server':
        rabbit_monitor_username => $novaconfig['rabbit_monitor_user'],
        rabbit_monitor_password => $novaconfig['rabbit_monitor_pass'],
    }

    class { '::openstack::adminscripts':
        novaconfig => $novaconfig
    }

    class { '::openstack::envscripts':
        novaconfig      => $novaconfig,
        designateconfig => $designateconfig
    }

    class { '::openstack::spreadcheck':
        novaconfig => $novaconfig
    }

    # TOBE: hiera'd
    $labs_vms = $novaconfig['fixed_range']
    $labs_metal = join(hiera('labs_baremetal_servers', []), ' ')
    $wikitech = ipresolve(hiera('labs_osm_host'),4)
    $horizon = ipresolve(hiera('labs_horizon_host'),4)
    $api_host = ipresolve(hiera('labs_nova_api_host'),4)
    $spare_master = ipresolve(hiera('labs_nova_controller_spare'),4)
    $designate = ipresolve(hiera('labs_designate_hostname'),4)
    $designate_secondary = ipresolve(hiera('labs_designate_hostname_secondary'))
    $monitoring = '208.80.154.14 208.80.153.74 208.80.155.119'
    $labs_nodes = hiera('labs_host_ips')

    # mysql access from iron
    ferm::service { 'mysql_iron':
        proto  => 'tcp',
        port   => '3306',
        srange => '@resolve(iron.wikimedia.org)',
    }

    # mysql monitoring access from tendril (db1011)
    ferm::service { 'mysql_tendril':
        proto  => 'tcp',
        port   => '3306',
        srange => '@resolve(tendril.wikimedia.org)',
    }

    $fwrules = {
        wikitech_ssh_public => {
            rule  => 'saddr (0.0.0.0/0) proto tcp dport (ssh) ACCEPT;',
        },
        dns_public => {
            rule  => 'saddr (0.0.0.0/0) proto (udp tcp) dport 53 ACCEPT;',
        },
        spice_consoles => {
            rule  => 'saddr (0.0.0.0/0) proto (udp tcp) dport 6082 ACCEPT;',
        },
        keystone_redis_replication => {
            rule  => "saddr (${spare_master}) proto tcp dport (6379) ACCEPT;",
        },
        wikitech_openstack_services => {
            rule  => "saddr (${wikitech} ${spare_master}) proto tcp dport (5000 35357 9292) ACCEPT;",
        },
        horizon_openstack_services => {
            rule  => "saddr ${horizon} proto tcp dport (5000 35357 9292) ACCEPT;",
        },
        keystone => {
            rule  => "saddr (${labs_nodes} ${spare_master} ${api_host} ${designate} ${designate_secondary}) proto tcp dport (5000 35357) ACCEPT;",
        },
        mysql_nova => {
            rule  => "saddr ${labs_nodes} proto tcp dport (3306) ACCEPT;",
        },
        beam_nova => {
            rule =>  "saddr ${labs_nodes} proto tcp dport (5672 56918) ACCEPT;",
        },
        rabbit_for_designate => {
            rule =>  "saddr ${designate} proto tcp dport 5672 ACCEPT;",
        },
        rabbit_for_nova_api => {
            rule =>  "saddr ${api_host} proto tcp dport 5672 ACCEPT;",
        },
        glance_api_nova => {
            rule => "saddr ${labs_nodes} proto tcp dport 9292 ACCEPT;",
        },
        salt => {
            rule => "saddr (${labs_vms} ${monitoring}) proto tcp dport (4505 4506) ACCEPT;",
        },
    }

    create_resources (ferm::rule, $fwrules)
}

class role::labs::openstack::nova::api {
    system::role { $name: }
    require openstack
    include role::labs::openstack::nova::common
    $novaconfig = $role::labs::openstack::nova::common::novaconfig

    class { '::openstack::nova::api':
        novaconfig        => $novaconfig,
    }
}

class role::labs::openstack::nova::network::bonding {
    interface::aggregate { 'bond1':
        orig_interface => 'eth1',
        members        => [ 'eth1', 'eth2', 'eth3' ],
    }
}

class role::labs::openstack::nova::network {

    require openstack
    system::role { $name: }
    include role::labs::openstack::nova::wikiupdates
    include role::labs::openstack::nova::common
    $novaconfig = $role::labs::openstack::nova::common::novaconfig

    interface::ip { 'openstack::network_service_public_dynamic_snat':
        interface => 'lo',
        address   => $novaconfig['network_public_ip'],
    }

    interface::tagged { $novaconfig['network_flat_interface']:
        base_interface => $novaconfig['network_flat_tagged_base_interface'],
        vlan_id        => $novaconfig['network_flat_interface_vlan'],
        method         => 'manual',
        up             => 'ip link set $IFACE up',
        down           => 'ip link set $IFACE down',
    }

    class { '::openstack::nova::network':
        novaconfig        => $novaconfig,
    }
}

class role::labs::openstack::nova::wikiupdates {
    require openstack
    if ! defined(Package['python-mwclient']) {
        package { 'python-mwclient':
            ensure => latest,
        }
    }

    file { '/usr/lib/python2.7/dist-packages/wikistatus':
        source  => "puppet:///modules/openstack/${::openstack::version}/nova/wikistatus",
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        require => Package['python-mwclient'],
        recurse => true,
    }

    file { '/usr/lib/python2.7/dist-packages/wikistatus.egg-info':
        source  => "puppet:///modules/openstack/${::openstack::version}/nova/wikistatus.egg-info",
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        require => Package['python-mwclient'],
        recurse => true,
    }
}

class role::labs::openstack::nova::compute($instance_dev='/dev/md1') {

    system::role { $name:
        description => 'openstack nova compute node',
    }

    require openstack
    include role::labs::openstack::nova::common
    $novaconfig = $role::labs::openstack::nova::common::novaconfig


    ganglia::plugin::python {'diskstat': }

    interface::tagged { $novaconfig['network_flat_interface']:
        base_interface => $novaconfig['network_flat_tagged_base_interface'],
        vlan_id        => $novaconfig['network_flat_interface_vlan'],
        method         => 'manual',
        up             => 'ip link set $IFACE up',
        down           => 'ip link set $IFACE down',
    }

    class { '::openstack::nova::compute':
        novaconfig => $novaconfig,
    }

    mount { '/var/lib/nova/instances':
        ensure  => mounted,
        device  => $instance_dev,
        fstype  => 'xfs',
        options => 'defaults',
    }

    file { '/var/lib/nova/instances':
        ensure  => directory,
        owner   => 'nova',
        group   => 'nova',
        require => Mount['/var/lib/nova/instances'],
    }

    if os_version('debian >= jessie || ubuntu >= trusty') {
        # Some older VMs have a hardcoded path to the emulator
        #  binary, /usr/bin/kvm.  Since the kvm/qemu reorg,
        #  new distros don't create a kvm binary.  We can safely
        #  alias kvm to qemu-system-x86_64 which keeps those old
        #  instances happy.
        file { '/usr/bin/kvm':
            ensure => link,
            target => '/usr/bin/qemu-system-x86_64',
        }
    }

    # Increase the size of conntrack table size (default is 65536)
    #  T139598
    sysctl::parameters { 'nova_conntrack':
        values => {
            'net.netfilter.nf_conntrack_max'                   => 262144,
            'net.netfilter.nf_conntrack_tcp_timeout_time_wait' => 65,
        },
    }

    file { '/etc/modprobe.d/nf_conntrack.conf':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        mode   => '0444',
        source => 'puppet:///modules/base/firewall/nf_conntrack.conf',
    }

    diamond::collector { 'LibvirtKVM':
        source   => 'puppet:///modules/diamond/collector/libvirtkvm.py',
        settings => {
            # lint:ignore:quoted_booleans
            # This is jammed straight into a config file, needs quoting.
            'sort_by_uuid' => 'true',
            'disk_stats'   => 'true',
            # lint:endignore
        }
    }

    # Starting with 3.18 (34666d467cbf1e2e3c7bb15a63eccfb582cdd71f) the netfilter code
    # was split from the bridge kernel module into a separate module (br_netfilter)
    if (versioncmp($::kernelversion, '3.18') >= 0) {

        # This directory is shipped by systemd, but trusty's upstart job for kmod also
        # parses /etc/modules-load.d/ (but doesn't create the directory).
        file { '/etc/modules-load.d/':
            ensure => 'directory',
            owner  => 'root',
            group  => 'root',
            mode   => '0755',
        }

        file { '/etc/modules-load.d/brnetfilter.conf':
            ensure  => present,
            owner   => 'root',
            group   => 'root',
            mode    => '0444',
            require => File['/etc/modules-load.d/'],
            content => "br_netfilter\n",
        }
    }

    require_package('conntrack')
}
