# Tools / scripts for helping manage the users in LDAP installation
# Note: This is for the so-called 'labs LDAP', which is used to manage
# both users on labs as well as access control for many things in prod
class role::openldap::management {

    require ::ldap::role::config::labs

    $ldapconfig = $ldap::role::config::labs::ldapconfig

    class { '::ldap::management':
        server   => $ldapconfig['servernames'][0],
        basedn   => $ldapconfig['basedn'],
        user     => $ldapconfig['script_user_dn'],
        password => $ldapconfig['script_user_pass'],
    }
}