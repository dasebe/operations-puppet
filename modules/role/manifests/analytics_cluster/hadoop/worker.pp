# == Class role::role::analytics_cluster::hadoop::worker
# Includes cdh::hadoop::worker classes
class role::analytics_cluster::hadoop::worker {
    system::role { 'role::analytics_cluster::hadoop::worker':
        description => 'Hadoop Worker (DataNode & NodeManager)',
    }

    require role::analytics_cluster::hadoop::client
    include role::analytics_cluster::monitoring::disks

    class { 'cdh::hadoop::worker': }

    # Use jmxtrans for sending metrics
    class { 'cdh::hadoop::jmxtrans::worker':
        statsd  => hiera('statsd'),
    }

    # Include icinga alerts if production realm.
    if $::realm == 'production' {
        # Icinga process alerts for DataNode and NodeManager
        nrpe::monitor_service { 'hadoop-hdfs-datanode':
            description   => 'Hadoop DataNode',
            nrpe_command  => '/usr/lib/nagios/plugins/check_procs -c 1:1 -C java -a "org.apache.hadoop.hdfs.server.datanode.DataNode"',
            contact_group => 'admins,analytics',
            require       => Class['cdh::hadoop::worker'],
        }
        nrpe::monitor_service { 'hadoop-yarn-nodemanager':
            description   => 'Hadoop NodeManager',
            nrpe_command  => '/usr/lib/nagios/plugins/check_procs -c 1:1 -C java -a "org.apache.hadoop.yarn.server.nodemanager.NodeManager"',
            contact_group => 'admins,analytics',
            require       => Class['cdh::hadoop::worker'],
        }

        # Alert on datanode mount disk space.  These mounts are ignored by the
        # base module's check_disk via the base::monitoring::host::nrpe_check_disk_options
        # override in worker.yaml hieradata.
        nrpe::monitor_service { 'disk_space_hadoop_worker':
            description   => 'Disk space on Hadoop worker',
            nrpe_command  => '/usr/lib/nagios/plugins/check_disk --units GB -w 32 -c 16 -e -l  -r "/var/lib/hadoop/data"',
            contact_group => 'admins,analytics',
        }

        # Make sure that this worker node has NodeManager running in a RUNNING state.
        # Install a custom check command for NodeManager Node-State:
        file { '/usr/local/lib/nagios/plugins/check_hadoop_yarn_node_state':
            source => 'puppet:///modules/role/analytics_cluster/hadoop/check_hadoop_yarn_node_state',
            owner  => 'root',
            group  => 'root',
            mode   => '0755',
        }
        nrpe::monitor_service { 'hadoop_yarn_node_state':
            description   => 'YARN NodeManager Node-State',
            nrpe_command  => '/usr/local/lib/nagios/plugins/check_hadoop_yarn_node_state',
            contact_group => 'admins,analytics',
        }
    }

    # hive::client is nice to have for jobs launched
    # from random worker nodes as app masters so they
    # have access to hive-site.xml and other hive jars.
    # This installs hive-hcatalog package on worker nodes to get
    # hcatalog jars, including Hive JsonSerde for using
    # JSON backed Hive tables.
    include role::analytics_cluster::hive::client

    # Spark Python stopped working in Spark 1.5.0 with Oozie,
    # for complicated reasons.  We need to be able to set
    # SPARK_HOME in an oozie launcher, and that SPARK_HOME
    # needs to point at a locally installed spark directory
    # in order load Spark Python dependencies.
    include cdh::spark

    # sqoop needs to be on worker nodes if Oozie is to
    # launch sqoop jobs.
    include cdh::sqoop

    # Install MaxMind databases for geocoding UDFs
    include geoip

    # Install packages that are useful for distributed
    # computation in Hadoop, and thus should be available on
    # any Hadoop nodes.
    require_package(
        # Need python3 on Hadoop nodes in order to run
        # Hadoop Streaming python jobs.
        'python3',
        'python-numpy',
        'python-pandas',
        'python-scipy',
        'python-requests',
        'python-matplotlib',
        'python-dateutil',
        'python-sympy',
        'python-docopt',
        'python3-docopt',
    )

    # This allows Hadoop daemons to talk to each other.
    ferm::service{ 'hadoop-access':
        proto  => 'tcp',
        port   => '1024:65535',
        srange => '$ANALYTICS_NETWORKS',
    }
}