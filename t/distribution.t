use v6;
use Zef::Utils::FileSystem;
use Zef::Utils::Distribution;
use Zef::Distribution;
use Test;


my sub gen-dist-files(*%d) {
    my &to-json := -> $o { Rakudo::Internals::JSON.to-json($o) }
    my $dist-dir = temp-path() andthen *.mkdir;
    $dist-dir.IO.child('META6.json').spurt(to-json(%d));
    for %d<provides> {
        my $to = $dist-dir.IO.child(.value) andthen {.parent.mkdir unless .parent.e}
        $to.spurt: (qq|unit module {.key};\n| ~ q|sub source-file is export {$?FILE}|);
    }
    return $dist-dir.IO;
}


subtest 'Distribution interfaces' => {
    my $old-dist-dir = gen-dist-files(:perl<6.c>,:name<XXX::Old>,:ver<1>, :api<1>, :auth<foo>, :provides(:XXX<lib/XXX.pm6>));
    my $new-dist-dir = gen-dist-files(:perl<6.c>,:name<XXX::New>,:ver<2>, :api<2>, :auth<foo>, :provides("XXX:api<3>" => 'lib/XXX.pm6'));

    my $old-dist = Zef::Distribution::FileSystem.new(prefix => $old-dist-dir);
    my $new-dist = Zef::Distribution::FileSystem.new(prefix => $new-dist-dir);

    # The role applied to any distributions used internally to enable easier searching/querying
    subtest 'Zef::Distribution' => {
        # see t/utils-distribution.t for the functional version of the remaining tests and associated comments/descriptions
        ok $old-dist.provides-matches-depspec("XXX");
        ok $new-dist.provides-matches-depspec("XXX");
        nok $old-dist.provides-matches-depspec("XXX::Old");
        nok $old-dist.provides-matches-depspec("XXX::Old");
        nok $new-dist.provides-matches-depspec("XXX::New");
        nok $new-dist.provides-matches-depspec("XXX::New");
        ok $old-dist.matches-depspec("XXX::Old");
        nok $old-dist.matches-depspec("XXX::New");
        nok $new-dist.matches-depspec("XXX::Old");
        ok $new-dist.matches-depspec("XXX::New");
        ok $old-dist.provides-matches-depspec("XX", :!strict);
        nok $new-dist.provides-matches-depspec("XY", :!strict);
        ok $old-dist.matches-depspec("XXX::O", :!strict);
        nok $new-dist.matches-depspec("XXX::O", :!strict);
        ok $old-dist.provides-matches-depspec("XXX:ver<1>");
        ok $new-dist.provides-matches-depspec("XXX:ver<2>");
        nok $old-dist.provides-matches-depspec("XXX:ver<2>");
        nok $new-dist.provides-matches-depspec("XXX:ver<1>");
        ok $old-dist.provides-matches-depspec("XXX:auth<foo>");
        ok $new-dist.provides-matches-depspec("XXX:auth<foo>");
        nok $old-dist.provides-matches-depspec("XXX:auth<bar>");
        nok $new-dist.provides-matches-depspec("XXX:auth<bar>");
        ok $old-dist.provides-matches-depspec("XXX:auth<foo>:ver<1>");
        ok $new-dist.provides-matches-depspec("XXX:auth<foo>:ver<2>");
        ok $old-dist.provides-matches-depspec("XXX:ver<1+>");
        ok $new-dist.provides-matches-depspec("XXX:ver<1+>");
        ok $new-dist.provides-matches-depspec("XXX:ver<2+>");
        ok $old-dist.matches-depspec("XXX::Old:api<1>");
        ok $old-dist.provides-matches-depspec("XXX:api<1>");
        nok $old-dist.provides-matches-depspec("XXX:api<2>");
        nok $old-dist.provides-matches-depspec("XXX::Old:api<2>");
        ok $new-dist.matches-depspec("XXX::New:api<2>");
        ok $new-dist.provides-matches-depspec("XXX:api<3>");
        nok $new-dist.provides-matches-depspec("XXX:api<2>");
        nok $new-dist.provides-matches-depspec("XXX::New:api<3>");
    }

    # A Distribution implementation similar to how a perl 5 module directory is laid out
    subtest 'Zef::Distribution::FileSystem' => {
        # installable
        ok $old-dist ~~ Distribution;
        ok $new-dist ~~ Distribution;

        # This can be fixed fairly easily in zef, but the various CompUnit::Repository
        # need to know how to parse depspec strings and how to find a matching depspec
        # string as a hash key. e.g. can't do:
        # - my $lookup-value = %provides{$shortname-to-lookup}
        # and instead must do something like:
        # - my $lookup-value = %provides.grep({ depspec-hash(.key)<name> eq $shortname-to-lookup }).map(*.value).head;
        is $old-dist.meta<provides><XXX>, 'lib/XXX.pm6';
        todo 'Provides lookup by key is NYI for module names with :adverbs', 1;
        is $new-dist.meta<provides><XXX>, 'lib/XXX.pm6';
        # This is how lookup/store for provides shortnames will have to work in rakudo/CUR
        is $new-dist.meta<provides>.first({ depspec-match('XXX', .key) }).value, 'lib/XXX.pm6';
        is $new-dist.provides-depspecs.map({ depspec-hash($_)<name> }).head, 'XXX';

        is $old-dist.meta<name>, 'XXX::Old';
        is $new-dist.meta<name>, 'XXX::New';
        is $old-dist.meta<ver>, 1;
        is $new-dist.meta<ver>, 2;
        is $old-dist.meta<api>, 1;
        is $new-dist.meta<api>, 2;

        subtest 'Installation' => {
            my $repo = CompUnit::RepositoryRegistry.repository-for-spec("inst#" ~ temp-path().child('my-repo').absolute);
            my $cu-depspec = CompUnit::DependencySpecification.new(:short-name<XXX>, :ver<1>);

            nok $repo.resolve($cu-depspec);
            ok $repo.install($old-dist);
            ok $repo.resolve($cu-depspec);

            # TODO: test $new-dist (see: 'Provides lookup by key is NYI' todo above)
        }
    }

    # An Distribution implementation that stores its file contents in the meta data itself (base64 encoded).
    # Primarily included so we can write tests without creating the various distribution files, and instead let
    # CURI create the files on-the-fly when they get installed.
    subtest 'Zef::Distribution::Hash' => {
        my %dist-hash-base64-meta = %(
            perl => '6.c',
            name => 'XXX::Old',
            ver  => '1',
            api  => '1',
            auth => 'foo',
            provides => {
                'XXX' => 'lib/XXX.pm6',
            },
            resources => [
                'config.txt',
                'libraries/foo'
            ],
            base64-inline-files => {
                "lib/XXX.pm6" => 'dW5pdCBtb2R1bGUgWFhYOyBvdXIgc3ViIHNvdXJjZS1maWxlIGlzIGV4cG9ydCB7ICQ/RklMRSB9',
                "resources/config.txt" => 'NDI=',
                "resources/libraries/foo" => 'cXdlcnR5',
                "bin/my-script" => 'dXNlIFhYWDsgc3ViIE1BSU4oKSB7IHNheSBzb3VyY2UtZmlsZSgpOyBzYXkgJT9SRVNPVVJDRVM8Y29uZmlnLnR4dD47IHNheSAlP1JFU09VUkNFUzxsaWJyYXJpZXMvZm9vPjsgZXhpdCAwIH0=',
            }
        );

        my $dist = Zef::Distribution::Hash.new(meta => %dist-hash-base64-meta);
        my $resource-universal-path = %dist-hash-base64-meta<base64-inline-files>.keys.first(*.starts-with('resources/libraries')).Str;
        my $resource-platform-path = $dist.meta<files>{$resource-universal-path};

        # sanity
        ok $dist ~~ Distribution;
        is $dist.meta<name>, 'XXX::Old';
        is $dist.meta<ver>, 1;
        is $dist.meta<api>, 1;

        # `files` bin/ scripts will be populated based on base64-inline-files that were passed in
        ok $dist.meta<files><resources/config.txt>;
        is $dist.meta<files>{$resource-universal-path}, $resource-platform-path;
        ok $dist.meta<files><bin/my-script>;

        # Cannot directly access distribution specific extension - base64-inline-files
        nok $dist.meta<base64-inline-files><lib/XXX.pm6>;
        nok $dist.meta<base64-inline-files><resources/config.txt>;
        nok $dist.meta<base64-inline-files><resources/libraries/foo>;
        nok $dist.meta<base64-inline-files><bin/my-script>;

        # Access to .content as usual, but transparently backed/decoded from base64-inline-files
        is $dist.content('lib/XXX.pm6').open(:bin).slurp.decode, 'unit module XXX; our sub source-file is export { $?FILE }';
        is $dist.content('resources/config.txt').open(:bin).slurp.decode, 42;
        is $dist.content($resource-platform-path).open(:bin).slurp.decode, 'qwerty';
        is $dist.content('bin/my-script').open(:bin).slurp.decode, 'use XXX; sub MAIN() { say source-file(); say %?RESOURCES<config.txt>; say %?RESOURCES<libraries/foo>; exit 0 }';

        subtest 'Installation' => {
            my $repo = CompUnit::RepositoryRegistry.repository-for-spec("inst#" ~ temp-path().child('my-repo').absolute);
            my $cu-depspec = CompUnit::DependencySpecification.new(:short-name<XXX>, :ver<1>);

            nok $repo.resolve($cu-depspec);
            ok $repo.install($dist);
            ok $repo.resolve($cu-depspec);
            ok not $repo.resolve($cu-depspec).distribution.meta<base64-inline-files>.defined, 'inline base64 data does not get installed with meta file';
        }
    }
}


done-testing;
