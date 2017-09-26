use v6;
use Zef::Utils::Distribution;
use Test;


subtest 'depspec-str/hash' => {
    # $shortspec is $longspec with any redundant information removed

    subtest 'Foo::Bar' => {
        my $shortspec = 'Foo::Bar';
        my $longspec  = 'Foo::Bar:api<*>:auth<>:ver<*>';
        my %hashspec  = %( :name<Foo::Bar>, :ver('*'), :api('*'), :auth('') );

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
        my %hashspec  = %( :name<Foo::Bar>, :ver('3'), :api('2'), :auth<foo@cpan.org> );

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
            my %hashspec  = %( :name<Foo::Bar-Baz>, :ver('3'), :api('2'), :auth<foo@cpan.org> );

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
            my %hashspec  = %( :name<Foo::Bar'Baz>, :ver('3'), :api('2'), :auth<foo@cpan.org> );

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
        my %hashspec  = %( :name<Foo>, :ver('1'), :api('*'), :auth('') );

        is-deeply depspec-hash($shortspec), %hashspec;
        is-deeply depspec-hash($longspec), %hashspec;
        is-deeply depspec-hash(%hashspec), %hashspec;
        is depspec-str(%hashspec), $longspec;
        is depspec-str($longspec), $longspec;
        is depspec-str($shortspec), $longspec;
    }

    subtest 'Multi-level depspec hash' => {
        my $longspec = 'Foo::Bar:api<*>:auth<>:ver<*>';
        my %dirtyhash = %( :name<Foo::Bar>, :ver('*'), :baz(:baz1(1), :baz2(2)) );
        my %cleanhash = %( :name<Foo::Bar>, :ver('*'), :api('*'), :auth('') );

        is-deeply depspec-hash($longspec), %cleanhash;
        is-deeply depspec-hash(%dirtyhash), %cleanhash;
        is-deeply depspec-hash(%cleanhash), %cleanhash;
        is depspec-str(%cleanhash), $longspec;
        is depspec-str(%dirtyhash), $longspec;
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
}

subtest 'resource-to-files' => {
    my %meta  = %( resources => ["config.json", "libraries/foo"], );
    my %files = resources-to-files(|%meta<resources>);

    is %files<resources/config.json>, 'resources/config.json';
    ok !%files<resources/libraries/foo>.ends-with('foo'); # will reflect platform specific changes
}


done-testing;
