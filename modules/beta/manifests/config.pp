# == Class: beta::config
#
# Shared configuration for beta classes
#
class beta::config {
    $bastion_ip = '10.68.21.205'  # IP address of deployment-tin

    # Networks to allow for rsync
    $rsync_networks = [
        '10.68.16.0/21',  # labs-eqiad
    ]

    # Directory where files to be scap'ed are staged
    $scap_stage_dir = '/srv/mediawiki-staging'

    # Directory where scap'ed files will be placed
    $scap_deploy_dir = '/srv/mediawiki'
}
