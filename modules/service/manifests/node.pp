# == Define: service::node
#
# service::node provides a common wrapper for setting up Node.js services
# based on service-template-node on. Note that most of
# the facts listed as parameters to this class are set correctly via
# Hiera. The only required parameter is the port. Alternatively, config
# may be given as well if needed.
#
# === Parameters
#
# [*enable*]
#   Whether or not the systemd unit or upstart job for the service
#   should be running. This is passed through to the underlying
#   base::service_unit resource. Default: true.
#
# [*port*]
#   Port on which to run the service
#
# [*config*]
#   The individual service's config to use. It can be eaither a hash of
#   key => value pairs, or a YAML-formatted string. Note that the complete
#   configuration will be assembled using the bits given here and common
#   node service configuration directives. If none is provided, we
#   assume the config  can be built from a template in a standard location
#
# [*full_config*]
#   Whether the full config has been provided by the caller. If set to true,
#   no config merging will take place and the caller is required to supply the
#   'config' parameter. Default: false
#
# [*no_workers*]
#   Number of workers to start. Default: 'ncpu' (i.e. start as many workers as
#   there are CPUs)
#
# [*heap_limit*]
#   Maximum amount of heap memory each worker is allowed to have in MBs. If
#   surpassed, the worker will be killed and a new one will be spawned. Default:
#   300
#
# [*heartbeat_to*]
#   Interval (in ms) used to monitor workers for activity. If $heartbeat_to
#   milliseconds pass without a worker sending a heartbeat, it will be killed by
#   the master. Default: 7500
#
# [*no_file*]
#   Number of maximum allowed open files for the service, to be set by
#   ulimit. Default: 10000
#
# [*healthcheck_url*]
#   The url to monitor the service at. 200 OK is the expected
#   answer. If has_spec it true, this is supposed to be the base url
#   for the spec request
#
# [*has_spec*]
#   If the service specifies a swagger spec, use it to thoroughly
#   monitor it
#
# [*repo*]
#   The name of the repo to use for deployment. Default: ${title}/deploy
#
# [*starter_module*]
#   The service's starter module loaded by service-runner on start-up. Default:
#   ./src/app.js
#
# [*entrypoint*]
#   If the service's starter module exports a specific function that should be
#   used on start-up, set this parameter to the function's name. Default: ''
#
# [*starter_script*]
#   The script used for starting the service. Default: src/server.js
#
# [*local_logging*]
#   Whether to store log entries on the target node as well. Default: true
#
# [*logging_name*]
#   The logging name to send to logstash. Default: $title
#
# [*statsd_prefix*]
#   The statsd metric prefix to use. Default: $title
#
# [*auto_refresh*]
#   Whether the service should be automatically restarted after config changes.
#   Default: true
#
# [*init_restart*]
#  Whether the service should be respawned by the init system in case of
#  crashes. Default: true
#
# [*environment*]
#  Environment variables that should be set in the service systemd or upstart unit.
#  Default: undef
#
# [*deployment*]
#   If this value is set to 'scap3' then deploy via scap3, otherwise,
#   use trebuchet
#   Default: undef
#
# [*deployment_user*]
#   The user that will own the service code. Only applicable when
#   $deployment =='scap3'. Default: $title
#
# [*deployment_config*]
#   Whether Scap3 is used for deploying the config as well. Applicable only when
#   $deployment == 'scap3'. Default: false
#
# [*deployment_vars*]
#   Extra variables to include in the puppet-controlled variables file. This
#   parameter's value is used only when the deployment method is Scap3 and the
#   service's configuration is deployed with it as well. Default: {}
#
# [*contact_groups*]
#   Contact groups for alerting.
#   Default: hiera('contactgroups', 'admins') - use 'contactgroups' hiera
#            variable with a fallback to 'admins' if 'contactgroups' isn't set.
#
# === Examples
#
# To set up a service named myservice on port 8520 and with a templated
# configuration, use:
#
#    service::node { 'myservice':
#        port   => 8520,
#        config => template('myservice/config.yaml.erb'),
#    }
#
# Likewise, you can supply the configuration directly as a hash:
#
#    service::node { 'myservice':
#        port   => 8520,
#        config => {
#            param1 => 'val1',
#            param2 => $myvar
#        },
#    }
#
# You can supply additional enviroment variables for the service systemd or upstart unit:
#
#    service::node { 'myservice':
#        port   => 8520,
#        environment => {
#           FOO => "bar",
#        },
#    }
#
#
define service::node(
    $port,
    $enable          = true,
    $config          = undef,
    $full_config     = false,
    $no_workers      = 'ncpu',
    $heap_limit      = 300,
    $heartbeat_to    = 7500,
    $no_file         = 10000,
    $healthcheck_url = '/_info',
    $has_spec        = false,
    $repo            = "${title}/deploy",
    $starter_module  = './src/app.js',
    $entrypoint      = '',
    $starter_script  = 'src/server.js',
    $local_logging   = true,
    $logging_name    = $title,
    $statsd_prefix   = $title,
    $auto_refresh    = true,
    $init_restart    = true,
    $environment     = undef,
    $deployment      = undef,
    $deployment_user = 'deploy-service',
    $deployment_config = false,
    $deployment_vars = {},
    $contact_groups  = hiera('contactgroups', 'admins'),
) {
    case $deployment {
        'scap3': {
            if ! defined(Service::Deploy::Trebuchet[$repo]) and ! defined(Scap::Target[$repo]) {
                require ::service::deploy::common
                scap::target { $repo:
                    service_name => $title,
                    deploy_user  => $deployment_user,
                    before       => Base::Service_unit[$title],
                    manage_user  => true,
                }
            }
            include ::scap::conftool
        }
        'git': {
            service::deploy::gitclone { $title:
                repository => $repo,
                before     => Base::Service_unit[$title],
            }
        }
        default: {
            if ! defined(Service::Deploy::Trebuchet[$repo]) {
                service::deploy::trebuchet{ $repo:
                    before => Base::Service_unit[$title]
                }
            }
        }
    }

    # Import all common configuration
    include service::configuration

    # we do not allow empty names
    unless $title and size($title) > 0 {
        fail('No name for this resource given!')
    }

    # sanity check since a default port cannot be assigned
    unless $port and $port =~ /^\d+$/ {
        fail('Service port must be specified and must be a number!')
    }

    # the local log file name
    $local_logdir = "${service::configuration::log_dir}/${title}"
    $local_logfile = "${local_logdir}/main.log"

    # configuration management
    if $full_config {
        unless $config and size($config) > 0 {
            fail('A config needs to be specified when full_config == true!')
        }
        $complete_config = $config
    } else {
        # load configuration
        $local_config = $config ? {
            undef   => '{}',
            default => $config
        }
        $complete_config = merge_config(
            template('service/node/config.yaml.erb'),
            $local_config
        )
    }

    # Software and the deployed code, firejail for containment
    require_package('nodejs', 'nodejs-legacy', 'firejail')

    # User/group
    group { $title:
        ensure => present,
        name   => $title,
        system => true,
        before => Service[$title],
    }

    user { $title:
        gid    => $title,
        home   => '/nonexistent',
        shell  => '/bin/false',
        system => true,
        before => Service[$title],
    }

    # Configuration, directories
    $conf_dir_gid = $deployment ? {
        'scap3' => $deployment_user,
        default => 'root',
    }
    file { "/etc/${title}":
        ensure => directory,
        owner  => 'root',
        group  => $conf_dir_gid,
        mode   => '0775',
    }

    if $deployment == 'scap3' and $deployment_config {
        # NOTE: this is a work-around need to switch config file deployments
        # to Scap3. The previous praxis was to make the config owned by root,
        # but that is not possible with Scap3, as it installs a symlink under
        # the $deployment_user user. chown'ing it will allow Scap3 to remove
        # the file and install its symlink
        $chown_user = "${deployment_user}:${deployment_user}"
        $chown_target = "/etc/${title}/config.yaml"
        exec { "chown ${chown_target}":
            command => "/bin/chown ${chown_user} ${chown_target}",
            # perform the chown only if root is the effective owner
            onlyif  => "/usr/bin/test -O ${chown_target}",
            require => [User[$deployment_user], Group[$deployment_user]]
        }
        file { "/etc/${title}/config-vars.yaml":
            ensure  => present,
            content => template('service/node/config-vars.yaml.erb'),
            owner   => $deployment_user,
            group   => $deployment_user,
            mode    => '0444',
            tag     => "${title}::config",
        }

        # We need to ensure that the full config gets deployed when we change the
        # puppet controlled part. If auto_refresh is true, this will also restart
        # the service.
        file { "/usr/local/bin/apply-config-${title}":
            ensure  => present,
            content => template('service/node/apply-config.sh.erb'),
            owner   => 'root',
            group   => 'root',
            mode    => '0755',
            before  => Exec["${title} config deploy"],
        }

        exec { "${title} config deploy":
                command     => "/usr/local/bin/apply-config-${title}",
                user        => $deployment_user,
                group       => $deployment_user,
                refreshonly => true,
                subscribe   => File["/etc/${title}/config-vars.yaml"],
        }

    } else {
        file { "/etc/${title}/config.yaml":
            ensure  => present,
            content => $complete_config,
            owner   => 'root',
            group   => 'root',
            mode    => '0444',
            tag     => "${title}::config",
        }
        if $auto_refresh {
            # if the service should be restarted after a
            # config change, specify the notify/before requirement
            File["/etc/${title}/config.yaml"] ~> Service[$title]
        } else {
            # no restart should happen, just ensure the file is
            # created before the service
            File["/etc/${title}/config.yaml"] -> Service[$title]
        }
    }

    # on systemd, set up redirecting of stdout/stderr to a file
    # that will be readable by any user.
    if $::initsystem == 'systemd' {
        systemd::syslog { $title:
            readable_by => 'all',
            base_dir    => $::service::configuration::log_dir,
            group       => 'root',
        }
    }
    elsif $local_logging {
        # Local logging is enabled, but we're
        # not on systemd
        file { $local_logdir:
            ensure => directory,
            owner  => $title,
            group  => 'root',
            mode   => '0755',
        }

        file { "/etc/logrotate.d/${title}":
            content => template('service/logrotate.erb'),
            owner   => 'root',
            group   => 'root',
            mode    => '0444',
        }
    }


    if $local_logging {
        # convenience script to pretty-print logs
        file { "/usr/local/bin/tail-${title}":
            content => template('service/node/tail-log.erb'),
            owner   => 'root',
            group   => 'root',
            mode    => '0755'
        }
        # we first placed tail-${title} in /usr/bin, so make sure
        # it's not there any more
        file { "/usr/bin/tail-${title}":
            ensure => absent,
        }

        # Ensure the local log directory is present before the service
        if $enable {
            File[$local_logdir] -> Service[$title]
        }
    }

    # service init script and activation
    base::service_unit { $title:
        ensure         => present,
        systemd        => true,
        upstart        => true,
        template_name  => 'node',
        refresh        => $auto_refresh,
        service_params => {
            enable     => $enable,
            ensure     => ensure_service($enable),
            hasstatus  => true,
            hasrestart => true,
        },
    }

    # Basic firewall
    ferm::service { $title:
        proto => 'tcp',
        port  => $port,
    }

    # Monitoring
    $ensure_monitoring = $enable ? {
        true  => 'present',
        false => 'absent',
    }

    if $has_spec {
        # Advanced monitoring
        include service::monitoring

        $monitor_url = "http://${::ipaddress}:${port}${healthcheck_url}"
        $check_command = "/usr/bin/service-checker-swagger -t 5 ${::ipaddress} ${monitor_url}"
        file { "/usr/local/bin/check-${title}":
            content => inline_template(
                '<%= ["#!/bin/sh", @check_command].join("\n") %>'
            ),
            owner   => 'root',
            group   => 'root',
            mode    => '0755',
        }
        nrpe::monitor_service{ "endpoints_${title}":
            ensure        => $ensure_monitoring,
            description   => "${title} endpoints health",
            nrpe_command  => "/usr/local/bin/check-${title}",
            subscribe     => File["/usr/local/bin/check-${title}"],
            contact_group => $contact_groups,
        }
        # we also support smart-releases
        service::deployment_script { $name:
            monitor_url     => $monitor_url,
            has_autorestart => $auto_refresh,
        }
    } else {
        # Basic monitoring
        monitoring::service { $title:
            ensure        => $ensure_monitoring,
            description   => $title,
            check_command => "check_http_port_url!${port}!${healthcheck_url}",
            contact_group => $contact_groups,
        }
    }

}
