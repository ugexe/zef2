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
        $dist-dir.IO.child(.key).spurt:
            (qq|unit module {.value};\n|
            ~ q|sub source-file is export {$?FILE}|);
    }
    return $dist-dir.IO;
}

subtest 'Zef::Distribution::FileSystem' => {
    my $old-dist-dir = gen-dist-files(:perl<6.c>,:name<XXX::Old>,:ver<1>, :api<1>, :auth<foo>, :provides(:XXX<lib/XXX.pm6>));
    my $new-dist-dir = gen-dist-files(:perl<6.c>,:name<XXX::New>,:ver<2>, :api<2>, :auth<foo>, :provides("XXX:api<3>" => 'lib/XXX.pm6'));

    my $old-dist = Zef::Distribution::FileSystem.new(prefix => $old-dist-dir);
    my $new-dist = Zef::Distribution::FileSystem.new(prefix => $new-dist-dir);

    # installable
    ok $old-dist ~~ Distribution;
    ok $new-dist ~~ Distribution;

    # query/searchable
    ok $old-dist ~~ Zef::Distribution;
    ok $new-dist ~~ Zef::Distribution;

    is $old-dist.meta<name>, 'XXX::Old';
    is $new-dist.meta<name>, 'XXX::New';
    is $old-dist.meta<ver>, 1;
    is $new-dist.meta<ver>, 2;
    is $old-dist.meta<api>, 1;
    is $new-dist.meta<api>, 2;

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

    ok $old-dist.provides-matches-depspec("XXX");
    ok $new-dist.provides-matches-depspec("XXX");

    # neither distribution is named after modules it provides, so needs .contains-spec to match
    nok $old-dist.provides-matches-depspec("XXX::Old");
    nok $old-dist.provides-matches-depspec("XXX::Old");
    nok $new-dist.provides-matches-depspec("XXX::New");
    nok $new-dist.provides-matches-depspec("XXX::New");
    ok $old-dist.matches-depspec("XXX::Old");
    nok $old-dist.matches-depspec("XXX::New");
    nok $new-dist.matches-depspec("XXX::Old");
    ok $new-dist.matches-depspec("XXX::New");

    # :!strict can be used to search for the short name portion as a prefix
    # e.g. `HTTP` would then match HTTP::UserAgent, HTTP::Server, etc
    ok $old-dist.provides-matches-depspec("XX", :!strict);
    nok $new-dist.provides-matches-depspec("XY", :!strict);
    ok $old-dist.matches-depspec("XXX::O", :!strict);
    nok $new-dist.matches-depspec("XXX::O", :!strict);

    # provides/depends can have adverbs on entries e.g. `"depends" : ["XXX:ver<1>"]`
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

    # make sure we:
    # A) automatically assume missing adverbs of provides mirror the distribution
    ok $old-dist.matches-depspec("XXX::Old:api<1>");
    ok $old-dist.provides-matches-depspec("XXX:api<1>");
    nok $old-dist.provides-matches-depspec("XXX:api<2>");
    nok $old-dist.provides-matches-depspec("XXX::Old:api<2>");
    # B) allow a provides to override the default distribution adverbs
    ok $new-dist.matches-depspec("XXX::New:api<2>");
    ok $new-dist.provides-matches-depspec("XXX:api<3>");
    nok $new-dist.provides-matches-depspec("XXX:api<2>");
    nok $new-dist.provides-matches-depspec("XXX::New:api<3>");

}


done-testing;
