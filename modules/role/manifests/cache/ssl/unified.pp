class role::cache::ssl::unified(
    $labs_server_name = 'beta.wmflabs.org',
    $labs_subjects = ['beta.wmflabs.org'],
) {
    if ( $::realm == 'production' ) {

        $check_cn = 'en.wikipedia.org'
        $check_sans = [
            'wikipedia.org',   '*.wikipedia.org',   '*.m.wikipedia.org', '*.zero.wikipedia.org',
            'wikimedia.org',   '*.wikimedia.org',   '*.m.wikimedia.org',
            'mediawiki.org',   '*.mediawiki.org',   '*.m.mediawiki.org',
            'wikibooks.org',   '*.wikibooks.org',   '*.m.wikibooks.org',
            'wikidata.org',    '*.wikidata.org',    '*.m.wikidata.org',
            'wikinews.org',    '*.wikinews.org',    '*.m.wikinews.org',
            'wikiquote.org',   '*.wikiquote.org',   '*.m.wikiquote.org',
            'wikisource.org',  '*.wikisource.org',  '*.m.wikisource.org',
            'wikiversity.org', '*.wikiversity.org', '*.m.wikiversity.org',
            'wikivoyage.org',  '*.wikivoyage.org',  '*.m.wikivoyage.org',
            'wiktionary.org',  '*.wiktionary.org',  '*.m.wiktionary.org',
            'wikimediafoundation.org', '*.wikimediafoundation.org', '*.m.wikimediafoundation.org',
            'w.wiki',
        ]

        $check_sans_str = inline_template('<%= @check_sans.join(",") %>')

        monitoring::service { 'https-ecdsa':
            description   => 'HTTPS Unified ECDSA',
            check_command => "check_ssl_unified!ECDSA!${check_cn}!${check_sans_str}",
        }

        monitoring::service { 'https-rsa':
            description   => 'HTTPS Unified RSA',
            check_command => "check_ssl_unified!RSA!${check_cn}!${check_sans_str}",
        }

        tlsproxy::localssl { 'unified':
            server_name    => 'www.wikimedia.org',
            certs          => ['ecc-uni.wikimedia.org', 'uni.wikimedia.org'],
            default_server => true,
            do_ocsp        => true,
            upstream_ports => [3120, 3121, 3122, 3123, 3124, 3125, 3126, 3127],
            redir_port     => 8080,
        }
    }
    else {
        tlsproxy::localssl { 'unified':
            server_name    => $labs_server_name,
            acme_subjects  => $labs_subjects,
            default_server => true,
            do_ocsp        => false,
            skip_private   => true,
            upstream_ports => [3120, 3121, 3122, 3123, 3124, 3125, 3126, 3127],
            redir_port     => 8080,
        }
    }

    # ordering ensures nginx/varnish config/service-start are
    #  not intermingled during initial install where they could
    #  have temporary conflicts on binding port 80
    Service['nginx'] -> Service<| tag == 'varnish_instance' |>
}
