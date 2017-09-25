use v6;
use Zef::Utils::Distribution;
use Test;


subtest 'from/to-depspec' => {
    # $shortspec is $longspec with any redundant information removed

    subtest 'Foo::Bar' => {
        my $shortspec = 'Foo::Bar';
        my $longspec  = 'Foo::Bar:api<*>:auth<>:ver<*>';
        my %hashspec  = %( :name<Foo::Bar>, :ver('*'), :api('*'), :auth('') );

        is-deeply from-depspec($shortspec), %hashspec;
        is-deeply from-depspec($longspec), %hashspec;
        is to-depspec(%hashspec), $longspec;
    }

    subtest 'Foo::Bar:api<2>:auth<foo@cpan.org>:ver<3>' => {
        my $shortspec = 'Foo::Bar:api<2>:auth<foo@cpan.org>:ver<3>';
        my $longspec  = 'Foo::Bar:api<2>:auth<foo@cpan.org>:ver<3>';
        my %hashspec  = %( :name<Foo::Bar>, :ver('3'), :api('2'), :auth<foo@cpan.org> );

        is-deeply from-depspec($shortspec), %hashspec;
        is-deeply from-depspec($longspec), %hashspec;
        is to-depspec(%hashspec), $longspec;
    }

    subtest 'apostrophy variants' => {
        subtest 'Foo::Bar-Baz:api<2>:auth<foo@cpan.org>:ver<3>' => {
            my $shortspec = 'Foo::Bar-Baz:api<2>:auth<foo@cpan.org>:ver<3>';
            my $longspec  = 'Foo::Bar-Baz:api<2>:auth<foo@cpan.org>:ver<3>';
            my %hashspec  = %( :name<Foo::Bar-Baz>, :ver('3'), :api('2'), :auth<foo@cpan.org> );

            is-deeply from-depspec($shortspec), %hashspec;
            is-deeply from-depspec($longspec), %hashspec;
            is to-depspec(%hashspec), $longspec;
        }

        subtest q|Foo::Bar'Baz:api<2>:auth<foo@cpan.org>:ver<3>| => {
            my $shortspec = q|Foo::Bar'Baz:api<2>:auth<foo@cpan.org>:ver<3>|;
            my $longspec  = q|Foo::Bar'Baz:api<2>:auth<foo@cpan.org>:ver<3>|;
            my %hashspec  = %( :name<Foo::Bar'Baz>, :ver('3'), :api('2'), :auth<foo@cpan.org> );

            is-deeply from-depspec($shortspec), %hashspec;
            is-deeply from-depspec($longspec), %hashspec;
            is to-depspec(%hashspec), $longspec;
        }
    }

    # Make sure $shortspec roundtrips back to :ver<> not :version<>, and that leading 'v' is stripped
    subtest 'Foo:version<v1>' => {
        my $shortspec = 'Foo:version<v1>';
        my $longspec  = 'Foo:api<*>:auth<>:ver<1>';
        my %hashspec  = %( :name<Foo>, :ver('1'), :api('*'), :auth('') );

        is-deeply from-depspec($shortspec), %hashspec;
        is-deeply from-depspec($longspec), %hashspec;
        is to-depspec(%hashspec), $longspec;
    }

    subtest 'Multi-level depspec hash' => {
        my $longspec  = 'Foo::Bar:api<*>:auth<>:ver<*>';
        my %hashspec  = %( :name<Foo::Bar>, :ver('*'), :baz(:baz1(1), :baz2(2)) );

        is to-depspec(%hashspec), $longspec;
    }

    subtest 'Invalid depspec strings' => {
        nok from-depspec(':');
        nok from-depspec('::');
        nok from-depspec('::Foo');
        nok from-depspec('Foo:');
        nok from-depspec('Foo::');
        nok from-depspec('Foo:Bar');
        nok from-depspec('Foo:::Bar');
        nok from-depspec('Foo:::Bar<foo>');
        nok from-depspec('Foo:::Bar::ver<foo>');
        nok from-depspec('Foo::Bar:ver');
        nok from-depspec('Foo::Bar:ver:auth<foo>');
        nok from-depspec('Foo::Bar:ver<1>::auth<foo>');
        nok from-depspec('1');
        nok from-depspec('Foo::1');
        nok from-depspec('-Foo::Bar');
        nok from-depspec('Foo::-Bar');
        nok from-depspec(q|'Foo::Bar|);
        nok from-depspec(q|Foo::'Bar|);
    }
}

subtest 'depspec-match' => {
    subtest 'sanity' => {
        my $concrete-depspec = 'Foo::Bar:ver<1>';
        my @matching-query-specs = 'Foo::Bar:ver<1>', 'Foo::Bar:ver<1.*>', 'Foo::Bar:ver<*>', 'Foo::Bar:ver<1.0>', 'Foo::Bar:ver<1.0+>';
        my @not-matching-query-specs = 'Foo::Bar:ver<1.1>', 'Foo::Bar:ver<1.1+>', 'Foo::Bar:ver<2.*>', 'Foo::Bar:ver<v1.0.1>', 'Foo::Bar:ver<9>';

        # Str, Str
        ok  depspec-match($concrete-depspec, $_) for @matching-query-specs;
        nok depspec-match($concrete-depspec, $_) for @not-matching-query-specs;
        # Str, Hash
        ok  depspec-match($concrete-depspec, from-depspec($_)) for @matching-query-specs;
        nok depspec-match($concrete-depspec, from-depspec($_)) for @not-matching-query-specs;
        # Hash, Str
        ok  depspec-match(from-depspec($concrete-depspec), $_) for @matching-query-specs;
        nok depspec-match(from-depspec($concrete-depspec), $_) for @not-matching-query-specs;
        # Hash, Hash
        ok  depspec-match(from-depspec($concrete-depspec), from-depspec($_)) for @matching-query-specs;
        nok depspec-match(from-depspec($concrete-depspec), from-depspec($_)) for @not-matching-query-specs;
    }

    subtest 'auth + version' => {
        my $concrete-depspec = 'Foo::Bar:ver<1>:auth<xxx>';
        my @matching-query-specs = 'Foo::Bar:ver<1>', 'Foo::Bar:ver<1.*>', 'Foo::Bar:ver<*>',
            'Foo::Bar:ver<1>:auth<xxx>', 'Foo::Bar:ver<1.*>:auth<xxx>', 'Foo::Bar:auth<xxx>:ver<*>';
        my @not-matching-query-specs = 'Foo::Bar:ver<1.1>', 'Foo::Bar:ver<1.1+>', 'Foo::Bar:ver<2.*>',
            'Foo::Bar:ver<2>:auth<xxx>', 'Foo::Bar:ver<1.*>:auth<foo@bar.net>', 'Foo::Bar:auth<*>:ver<*>';

        ok  depspec-match($concrete-depspec, $_) for @matching-query-specs;
        nok depspec-match($concrete-depspec, $_) for @not-matching-query-specs;

    }
}

subtest 'resource-to-files' => {
    my %meta  = %( resources => ["config.json", "libraries/foo"], );
    my %files = resources-to-files(|%meta<resources>);

    is %files<config.json>, 'resources/config.json';
    ok !%files<libraries/foo>.ends-with('foo'); # will reflect platform specific changes
}


done-testing;
