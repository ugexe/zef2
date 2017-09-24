use v6;
use Zef::Utils::FileSystem;
use Zef::Utils::IO;
use Test;


my sub to-json($str) { Rakudo::Internals::JSON.from-json($str) }

ok FETCH('https://httpbin.org/user-agent', temp-path()).result.slurp.&to-json<user-agent> ~~ /:i rakudo/, 'Basic fetch test';

my $git-url     = 'git://github.com/ugexe/Perl6-Net--HTTP.git';
my $git-url-rev = 'https://github.com/ugexe/Perl6-Net--HTTP.git@1b221c1d0946ff91f4a1c612153ed4d974aa7351';
my $tar-url     = 'https://github.com/ugexe/Perl6-Net--HTTP/archive/master.tar.gz';
my $zip-url     = 'https://github.com/ugexe/Perl6-Net--HTTP/archive/master.zip';

subtest 'Basic uri fetch/list/extract' => {
    for ($tar-url, $zip-url, $git-url) -> $url  {
        my $saved-to = FETCH($url, temp-path().child($url.IO.basename)).result;
        ok $saved-to.e, "FETCH $url -> $saved-to";

        my @extractable-paths = PATHS($saved-to).result;
        ok @extractable-paths.first(*.ends-with('META6.json'));

        my $extracted-to = EXTRACT($saved-to, temp-path()).result;
        is $extracted-to.dir.elems, 1, 'Expected number of paths found in root of extracted target directory';
        ok $extracted-to.dir.first(*.d).child('META6.json').f, "EXTRACT $saved-to -> $extracted-to";

        # Cheat and do the local path variant of FETCH from Zef::Utils::FileSystem
        once {
            my $uri = $extracted-to;
            temp $saved-to = FETCH($uri, temp-path().child($uri.basename)).result;
            ok $saved-to.e, "FETCH $uri -> $saved-to";

            temp @extractable-paths = PATHS($saved-to).result;
            ok @extractable-paths.first(*.ends-with('META6.json'));

            my $extract-to = temp-path('/' ~ $saved-to.basename);
            temp $extracted-to = EXTRACT($saved-to, temp-path($extract-to.basename)).result;
            is $extracted-to.dir.elems, 1, 'Expected number of paths found in root of extracted target directory';
            ok $extracted-to.dir.first(*.d).child('META6.json').f, "EXTRACT $saved-to -> $extracted-to";
        }
    }
}

subtest 'Ensure FETCH/EXTRACT handle git revisions correct' => {
    for ($git-url-rev) -> $url {
        my $saved-to = FETCH($url, temp-path().child($url.IO.basename)).result;
        ok $saved-to.e;

        my @extractable-paths = PATHS($saved-to).result;
        ok @extractable-paths.first(*.ends-with('META6.json'));

        my $extracted-to = EXTRACT($saved-to, temp-path()).result;
        is $extracted-to.dir.elems, 1, 'Expected number of paths found in root of extracted target directory';
        ok $extracted-to.dir.first(*.d).child('META6.json').f, "EXTRACT $saved-to -> $extracted-to";
        is to-json($extracted-to.dir.first(*.d).child('META6.json').slurp)<version>, '0.0.4';
    }
}


done-testing;
