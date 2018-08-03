use v6;
use Zef::Utils::Distribution;
use Test;


subtest 'depspec-str/hash' => {
    # $shortspec is $longspec with any redundant information removed

    subtest 'Foo::Bar' => {
        my $shortspec = 'Foo::Bar';
        my $longspec  = 'Foo::Bar:api<*>:auth<>:ver<*>';
        my %hashspec  = :name<Foo::Bar>, :ver('*'), :api('*'), :auth('');

        is-deeply depspec-hash($shortspec), %hashspec;
        is-deeply depspec-hash($longspec), %hashspec;
        is-deeply depspec-hash(%hashspec), %hashspec;
        is depspec-str(%hashspec), $longspec;
        is depspec-str($longspec), $longspec;
        is depspec-str($shortspec), $longspec;
    }

    subtest 'Foo::Bar:api<2>:auth<foo@cpan.org>:ver<3>' => {
        my $shortspec = 'Foo::Bar:api<2>:auth<foo@cpan.org>:ver<3>';
        my $longspec  = 'Foo::Bar:api<2>:auth<foo@cpan.org>:ver<3>';
        my %hashspec  = :name<Foo::Bar>, :ver('3'), :api('2'), :auth<foo@cpan.org>;

        is-deeply depspec-hash($shortspec), %hashspec;
        is-deeply depspec-hash($longspec), %hashspec;
        is-deeply depspec-hash(%hashspec), %hashspec;
        is depspec-str(%hashspec), $longspec;
        is depspec-str($longspec), $longspec;
        is depspec-str($shortspec), $longspec;
    }

    subtest 'apostrophy variants' => {
        subtest 'Foo::Bar-Baz:api<2>:auth<foo@cpan.org>:ver<3>' => {
            my $shortspec = 'Foo::Bar-Baz:api<2>:auth<foo@cpan.org>:ver<3>';
            my $longspec  = 'Foo::Bar-Baz:api<2>:auth<foo@cpan.org>:ver<3>';
            my %hashspec  = :name<Foo::Bar-Baz>, :ver('3'), :api('2'), :auth<foo@cpan.org>;

            is-deeply depspec-hash($shortspec), %hashspec;
            is-deeply depspec-hash($longspec), %hashspec;
            is-deeply depspec-hash(%hashspec), %hashspec;
            is depspec-str(%hashspec), $longspec;
            is depspec-str($longspec), $longspec;
            is depspec-str($shortspec), $longspec;
        }

        subtest q|Foo::Bar'Baz:api<2>:auth<foo@cpan.org>:ver<3>| => {
            my $shortspec = q|Foo::Bar'Baz:api<2>:auth<foo@cpan.org>:ver<3>|;
            my $longspec  = q|Foo::Bar'Baz:api<2>:auth<foo@cpan.org>:ver<3>|;
            my %hashspec  = :name<Foo::Bar'Baz>, :ver('3'), :api('2'), :auth<foo@cpan.org>;

            is-deeply depspec-hash($shortspec), %hashspec;
            is-deeply depspec-hash($longspec), %hashspec;
            is-deeply depspec-hash(%hashspec), %hashspec;
            is depspec-str(%hashspec), $longspec;
            is depspec-str($longspec), $longspec;
            is depspec-str($shortspec), $longspec;
        }
    }

    # Make sure $shortspec roundtrips back to :ver<> not :version<>, and that leading 'v' is stripped
    subtest 'Foo:version<v1>' => {
        my $shortspec = 'Foo:version<v1>';
        my $longspec  = 'Foo:api<*>:auth<>:ver<1>';
        my %hashspec  = :name<Foo>, :ver('1'), :api('*'), :auth('');

        is-deeply depspec-hash($shortspec), %hashspec;
        is-deeply depspec-hash($longspec), %hashspec;
        is-deeply depspec-hash(%hashspec), %hashspec;
        is depspec-str(%hashspec), $longspec;
        is depspec-str($longspec), $longspec;
        is depspec-str($shortspec), $longspec;
    }

    subtest 'Angle quotes inside depspec field value' => {
        my $dirty-shortspec = 'Bar::Baz:auth<CPAN:UGEXE <firstlast@cpan.org>>';
        my $dirty-longspec  = 'Bar::Baz:api<*>:auth<CPAN:UGEXE <firstlast@cpan.org>>>:ver<*>';
        my $clean-shortspec = 'Bar::Baz:auth<CPAN:UGEXE \<firstlast@cpan.org\>>';
        my $clean-longspec  = 'Bar::Baz:api<*>:auth<'
            ~ 'CPAN:UGEXE \<firstlast@cpan.org\>' # Testing this line - contains escaped quotes (> and <) and a colon
            ~ '>:ver<*>';
        my %dirty-hashspec = :name<Bar::Baz>, :ver('*'), :api('*'), :auth(q|CPAN:UGEXE <firstlast@cpan.org>|);
        my %clean-hashspec = :name<Bar::Baz>, :ver('*'), :api('*'), :auth(q|CPAN:UGEXE \<firstlast@cpan.org\>|);

        is-deeply depspec-hash($clean-shortspec), %clean-hashspec;
        is-deeply depspec-hash($clean-longspec), %clean-hashspec;
        is-deeply depspec-hash(%clean-hashspec), %clean-hashspec;
        is-deeply depspec-hash(%dirty-hashspec), %clean-hashspec;
        is depspec-str(%dirty-hashspec), $clean-longspec;
        is depspec-str(%clean-hashspec), $clean-longspec;
        is depspec-str($clean-longspec), $clean-longspec;
        is depspec-str($clean-shortspec), $clean-longspec;

        # so remember: only < and > need to be quoted in the string form of depspec, not values of the hash form depspec
        nok depspec-str($dirty-longspec);
        nok depspec-str($dirty-shortspec);
        ok depspec-str(%dirty-hashspec);
    }

    subtest 'Multi-level depspec hash' => {
        my $longspec = 'Foo::Bar:api<*>:auth<>:ver<*>';
        my %dirty-hashspec = :name<Foo::Bar>, :ver('*'), :baz(:baz1(1), :baz2(2));
        my %clean-hashspec = :name<Foo::Bar>, :ver('*'), :api('*'), :auth('');

        is-deeply depspec-hash($longspec), %clean-hashspec;
        is-deeply depspec-hash(%dirty-hashspec), %clean-hashspec;
        is-deeply depspec-hash(%clean-hashspec), %clean-hashspec;
        is depspec-str(%clean-hashspec), $longspec;
        is depspec-str(%dirty-hashspec), $longspec;
        is depspec-str($longspec), $longspec;
    }

    subtest 'Invalid depspec strings' => {
        my @invalid = ':', '::', '::Foo', 'Foo:', 'Foo::', 'Foo:Bar', 'Foo:::Bar', 'Foo:::Bar<foo>',
            'Foo:::Bar::ver<foo>', 'Foo::Bar:ver', 'Foo::Bar:ver:auth<foo>', 'Foo::Bar:ver<1>::auth<foo>',
            '1', 'Foo::1', '-Foo::Bar', 'Foo::-Bar', q|'Foo::Bar|, q|Foo::'Bar|;

        nok depspec-hash($_) for @invalid;
        nok depspec-str($_)  for @invalid;
    }
}

subtest 'depspec-match' => {
    subtest 'sanity' => {
        my $haystack-depspec = 'Foo::Bar:ver<1>';
        my @matching-needle-depspecs = 'Foo::Bar:ver<1>', 'Foo::Bar:ver<1.*>', 'Foo::Bar:ver<*>', 'Foo::Bar:ver<1.0>', 'Foo::Bar:ver<1.0+>';
        my @nonmatching-needle-depspecs = 'Foo::Bar:ver<1.1>', 'Foo::Bar:ver<1.1+>', 'Foo::Bar:ver<2.*>', 'Foo::Bar:ver<v1.0.1>', 'Foo::Bar:ver<9>';

        # Test all variants of hash or str specs that could be passed to depspec-match

        # Str, Str
        ok  depspec-match($_, $haystack-depspec) for @matching-needle-depspecs;
        nok depspec-match($_, $haystack-depspec) for @nonmatching-needle-depspecs;
        # Str, Hash
        ok  depspec-match(depspec-hash($_), $haystack-depspec) for @matching-needle-depspecs;
        nok depspec-match(depspec-hash($_), $haystack-depspec) for @nonmatching-needle-depspecs;
        # Hash, Str
        ok  depspec-match($_, depspec-hash($haystack-depspec)) for @matching-needle-depspecs;
        nok depspec-match($_, depspec-hash($haystack-depspec)) for @nonmatching-needle-depspecs;
        # Hash, Hash
        ok  depspec-match(depspec-hash($_), depspec-hash($haystack-depspec)) for @matching-needle-depspecs;
        nok depspec-match(depspec-hash($_), depspec-hash($haystack-depspec)) for @nonmatching-needle-depspecs;
    }

    subtest 'auth + version' => {
        my $haystack-depspec = 'Foo::Bar:ver<1>:auth<xxx>';
        my @matching-needle-depspecs = 'Foo::Bar:ver<1>', 'Foo::Bar:ver<1.*>', 'Foo::Bar:ver<*>',
            'Foo::Bar:ver<1>:auth<xxx>', 'Foo::Bar:ver<1.*>:auth<xxx>', 'Foo::Bar:auth<xxx>:ver<*>';
        my @nonmatching-needle-depspecs = 'Foo::Bar:ver<1.1>', 'Foo::Bar:ver<1.1+>', 'Foo::Bar:ver<2.*>',
            'Foo::Bar:ver<2>:auth<xxx>', 'Foo::Bar:ver<1.*>:auth<foo@bar.net>', 'Foo::Bar:auth<*>:ver<*>';

        ok  depspec-match($_, $haystack-depspec) for @matching-needle-depspecs;
        nok depspec-match($_, $haystack-depspec) for @nonmatching-needle-depspecs;
    }

    subtest ':!strict' => {
        my $haystack-depspec = 'Foo::Bar:ver<1>';
        my @matching-needle-depspecs = 'Foo:ver<1>', 'Foo', 'Foo::Bar:ver<*>', 'F', 'Foo:ver<*>';
        my @nonmatching-needle-depspecs = 'Foo::Baz:ver<1>', 'Foo::Foo:ver<1.*>', 'Foo::X:ver<*>', 'Fooo:ver<1.0>', 'FooBar:ver<1.0+>',
            'Foo::Bar:ver<1.1>', 'Foo::Bar:ver<1.1+>', 'Foo::Bar:ver<2.*>', 'Foo::Bar:ver<v1.0.1>', 'Foo::Bar:ver<9>';

        # Str, Str
        ok  depspec-match($_, $haystack-depspec, :!strict) for @matching-needle-depspecs;
        nok depspec-match($_, $haystack-depspec, :!strict) for @nonmatching-needle-depspecs;
    }
}

subtest 'depspec-sort' => {
    subtest 'version/api sort order' => {
        my $sorted-dists = (
            %( :name<XXX>, :ver<1.1>,      :api<1>, ),
            %( :name<XXX>, :version<1.11>, :api<1>, ),
            %( :name<XXX>, :ver<1.200>,    :api<1>, ),
            %( :name<XXX>, :ver<2>,        :api<1>, ),
            %( :name<XXX>, :ver<2>,        :api<2>, ),
        );

        is-deeply( depspec-sort($_), $sorted-dists ) for $sorted-dists.permutations;
    }

    subtest 'sort meta data hashes' => {
        my $sorted-dists = (
            %( :perl<6.c>, :name<XXX>,          :api<2>, :auth<foo>, :provides(:XXX<lib/XXX.pm6>) ),
            %( :perl<6.c>, :name<XXX>, :ver<1>, :api<1>,             :provides(:XXX<lib/XXX.pm6>) ),
            %( :perl<6.c>, :name<XXX>, :ver<2>,          :auth<bar>, :provides(:XXX<lib/XXX.pm6>) ),
        );

        is-deeply( depspec-sort($_), $sorted-dists ) for $sorted-dists.permutations;
    }
}

subtest 'provides-depspecs' => {
    my %old-dist-meta = :perl<6.c>, :name<XXX::Old>,:ver<1>, :api<1>, :auth<foo>, :provides(:XXX<lib/XXX.pm6>);
    my %new-dist-meta = :perl<6.c>, :name<XXX::New>,:ver<2>, :api<2>, :auth<foo>, :provides("XXX:api<3>" => 'lib/XXX.pm6');

    ok %old-dist-meta<provides><XXX>;
    nok %new-dist-meta<provides><XXX>; # todo: find a way to make this work
    is provides-depspecs(%old-dist-meta).map({ depspec-hash($_)<name> }).head, 'XXX';
    is provides-depspecs(%new-dist-meta).map({ depspec-hash($_)<name> }).head, 'XXX';
    is provides-depspecs(%old-dist-meta).map({ depspec-hash($_)<api> }).head, 1;
    is provides-depspecs(%new-dist-meta).map({ depspec-hash($_)<api> }).head, 3;
}

subtest 'environment-query' => {
    my %native-depspec =
            from => "native",
            name => {
                "by-distro.name" => {
                    "win32"  => "win",
                    ""       => "unknown",
                }
            };

    my $shortname = $*DISTRO.is-win ?? "win32" !! "unknown";
    my $longspec   = "{$shortname}:api<*>:auth<>:from<native>:ver<*>";
    my %hashspec   = :name($shortname), :from("native");

    is-deeply environment-query(%native-depspec), %hashspec;
    is depspec-str(environment-query(%native-depspec)), $longspec;
}

subtest 'depends-depspecs' => {
    my %dist-meta =
        :perl<6.c>,
        :name<XXX>,
        :provides(:XXX('lib/XXX.pm6')),
        :depends(
            'Foo::Bar',
            ('JSON::Foo', 'JSON::Bar:ver<2>'),
            'Baz:ver<1>:api<*>:auth<foo@bar.net>',
            {
                from => "native",
                name => {
                    "by-distro.name" => {
                        "win32"  => "win",
                        ""       => "unknown",
                    }
                }
            },
        );

    my $expected-depends-depspecs = (
        {:api("*"), :auth(""), :name("Foo::Bar"), :ver("*")},
        (
            {:api("*"), :auth(""), :name("JSON::Foo"), :ver("*")},
            {:api("*"), :auth(""), :name("JSON::Bar"), :ver("2")}
        ),
        {:api("*"), :auth("foo\@bar.net"), :name("Baz"), :ver("1")},
        {:api("*"), :auth(""), :from("native"), :name($*DISTRO.is-win ?? "win32" !! "unknown"), :ver("*")},
    );

    is-deeply depends-depspecs(%dist-meta<depends>.list), $expected-depends-depspecs;
}

subtest '[provides-]?matches-depspec' => {
    my %old-dist-meta = :perl<6.c>, :name<XXX::Old>,:ver<1>, :api<1>, :auth<foo>, :provides(:XXX<lib/XXX.pm6>);
    my %new-dist-meta = :perl<6.c>, :name<XXX::New>,:ver<2>, :api<2>, :auth<foo>, :provides("XXX:api<3>" => 'lib/XXX.pm6');

    # both have an `XXX` module in their provides section
    ok provides-matches-depspec("XXX", %old-dist-meta);
    ok provides-matches-depspec("XXX", %new-dist-meta);

    # neither distribution is named after modules it provides, so needs matches-depspec to match
    nok provides-matches-depspec("XXX::Old", %old-dist-meta);
    nok provides-matches-depspec("XXX::Old", %old-dist-meta);
    nok provides-matches-depspec("XXX::New", %new-dist-meta);
    nok provides-matches-depspec("XXX::New", %new-dist-meta);
    ok matches-depspec("XXX::Old", %old-dist-meta);
    nok matches-depspec("XXX::New", %old-dist-meta);
    nok matches-depspec("XXX::Old", %new-dist-meta);
    ok matches-depspec("XXX::New", %new-dist-meta);

    # :!strict can be used to search for the short name portion as a prefix
    # e.g. `HTTP` would then match HTTP::UserAgent, HTTP::Server, etc
    ok provides-matches-depspec("XX", %old-dist-meta, :!strict);
    nok provides-matches-depspec("XY", %new-dist-meta, :!strict);
    ok matches-depspec("XXX::O", %old-dist-meta, :!strict);
    nok matches-depspec("XXX::O", %new-dist-meta, :!strict);

    # provides/depends can have adverbs on entries e.g. `"depends" : ["XXX:ver<1>"]`
    ok provides-matches-depspec("XXX:ver<1>", %old-dist-meta);
    ok provides-matches-depspec("XXX:ver<2>", %new-dist-meta);
    nok provides-matches-depspec("XXX:ver<2>", %old-dist-meta);
    nok provides-matches-depspec("XXX:ver<1>", %new-dist-meta);

    ok provides-matches-depspec("XXX:auth<foo>", %old-dist-meta);
    ok provides-matches-depspec("XXX:auth<foo>", %new-dist-meta);
    nok provides-matches-depspec("XXX:auth<bar>", %old-dist-meta);
    nok provides-matches-depspec("XXX:auth<bar>", %new-dist-meta);

    ok provides-matches-depspec("XXX:auth<foo>:ver<1>", %old-dist-meta);
    ok provides-matches-depspec("XXX:auth<foo>:ver<2>", %new-dist-meta);

    ok provides-matches-depspec("XXX:ver<1+>", %old-dist-meta);
    ok provides-matches-depspec("XXX:ver<1+>", %new-dist-meta);
    ok provides-matches-depspec("XXX:ver<2+>", %new-dist-meta);

    # make sure we:
    # A) automatically assume missing adverbs of provides mirror the distribution
    ok matches-depspec("XXX::Old:api<1>", %old-dist-meta);
    ok provides-matches-depspec("XXX:api<1>", %old-dist-meta);
    nok provides-matches-depspec("XXX:api<2>", %old-dist-meta);
    nok provides-matches-depspec("XXX::Old:api<2>", %old-dist-meta);
    # B) allow a provides to override the default distribution adverbs
    ok matches-depspec("XXX::New:api<2>", %new-dist-meta);
    ok provides-matches-depspec("XXX:api<3>", %new-dist-meta);
    nok provides-matches-depspec("XXX:api<2>", %new-dist-meta);
    nok provides-matches-depspec("XXX::New:api<3>", %new-dist-meta);
}

subtest 'resource-to-files' => {
    my %meta  = :perl<6.c>, :name<XXX>, :resources(<config.json libraries/foo>);
    my %files = resources-to-files(|%meta<resources>);

    is %files<resources/config.json>, 'resources/config.json';
    ok !%files<resources/libraries/foo>.ends-with('foo'); # will reflect platform specific changes
}


done-testing;
