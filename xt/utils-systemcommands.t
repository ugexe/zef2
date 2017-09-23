use v6;
use Zef::Utils::SystemCommands :ALL;
use Zef::Utils::FileSystem;
use Test;


my sub to-json($str) { Rakudo::Internals::JSON.from-json($str) }

my $http-url = 'https://httpbin.org/user-agent';
my $git-url  = 'git://github.com/ugexe/P6TCI.git';
my $tar-url  = 'https://github.com/ugexe/P6TCI/archive/master.tar.gz';
my $zip-url  = 'https://github.com/ugexe/P6TCI/archive/master.zip';

my &temp-path = -> {
    my $path = $*TMPDIR.child("zef").child("{time}.{$*PID}/{(^100000).pick}") andthen *.parent.mkdir;
    END { try delete-paths($path, :r, :d, :f, :dot) }
    $path;
}

if has-git() {
    subtest 'git - basic' => {
        my $archive-path = &temp-path(); # a directory, so don't add ext
        await git-clone($git-url, $archive-path);
        ok $archive-path.child('META6.json').f;
        ok git-ls-tree($archive-path).result.first(*.ends-with('META6.json'));

        my $extract-to = &temp-path() andthen *.mkdir;
        await git-extract($archive-path, $extract-to);
        ok $extract-to.e;
        is $extract-to.dir.elems, 1;
        ok $extract-to.dir.first(*.d).child('META6.json').f;
    }

    subtest 'git - specific revisions' => {
        my $rev1-sha1 = '51d85bd0a97d54235c0de624bf0577655348c38b';
        my $rev2-sha1 = '1b221c1d0946ff91f4a1c612153ed4d974aa7351';
        my $git-url-rev1 = "https://github.com/ugexe/Perl6-Net--HTTP.git@rev1-sha1";
        my $git-url-rev2 = "https://github.com/ugexe/Perl6-Net--HTTP.git@$rev2-sha1";

        my $archive-path-rev1 = &temp-path();
        my $archive-path-rev2 = &temp-path(); 
        await git-clone($git-url-rev1, $archive-path-rev1);
        await git-clone($git-url-rev2, $archive-path-rev2);
        ok $archive-path-rev1.child('META6.json').f;
        ok $archive-path-rev2.child('META6.json').f;

        my $extract-to-rev1 = &temp-path() andthen *.mkdir;
        my $extract-to-rev2 = &temp-path() andthen *.mkdir;

        ok git-ls-tree($archive-path-rev1).result.first(*.ends-with('META6.json'));
        # todo: test for changes in files between $some-revision and HEAD, like META.info -> META6.json
        ok git-ls-tree($archive-path-rev2).result.first(*.ends-with('META6.json'));

        await git-extract($archive-path-rev1, $extract-to-rev1, $rev1-sha1);
        await git-extract($archive-path-rev2, $extract-to-rev2, $rev2-sha1);

        ok $extract-to-rev1.e;
        is $extract-to-rev1.dir.elems, 1;
        ok $extract-to-rev1.dir.first(*.d).child('META6.json').f;
        is to-json($extract-to-rev1.dir.first(*.d).child('META6.json').slurp)<version>, '0.0.5';

        ok $extract-to-rev2.e;
        is $extract-to-rev2.dir.elems, 1;
        ok $extract-to-rev2.dir.first(*.d).child('META6.json').f;
        is to-json($extract-to-rev2.dir.first(*.d).child('META6.json').slurp)<version>, '0.0.4';
    }
}

if has-curl() && has-tar() && has-p5tar() {
    subtest 'curl / tar' => {
        subtest 'curl' => {
            my $path = &temp-path();
            ok curl($http-url, $path).so;
            ok $path.slurp.&to-json<user-agent> ~~ /:i rakudo/;
        }

        my $archive-path = &temp-path() ~ '.tar.gz';
        await curl($tar-url, $archive-path);

        subtest 'tar' => {
            ok tar-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = &temp-path() andthen *.mkdir;
            await tar-extract($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }

        subtest 'p5tar' => {
            ok p5tar-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = &temp-path() andthen *.mkdir;
            await p5tar-extract($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }
    }
}

if has-wget() && has-unzip() {
    subtest 'wget / unzip' => {
        my $path = &temp-path();
        ok wget($http-url, $path).so;
        ok $path.slurp.&to-json<user-agent> ~~ /:i rakudo/;

        my $archive-path = &temp-path() ~ '.zip';
        await wget($zip-url, $archive-path);

        subtest 'unzip' => {
            ok unzip-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = &temp-path() andthen *.mkdir;
            await unzip-extract($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }
    }
}

if has-powershell() {
    subtest 'powershell' => {
        subtest 'powershell-client' => {
            my $path = &temp-path();
            ok powershell-client($http-url, $path).so;
            ok $path.slurp.&to-json<user-agent> ~~ /:i rakudo/;
        }

        subtest 'powershell-unzip' => {
            my $archive-path = &temp-path() ~ '.zip';
            await powershell-client($zip-url, $archive-path);
            ok powershell-unzip-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = &temp-path() andthen *.mkdir;
            await powershell-unzip($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }

        if has-unzip() {
            subtest 'unzip' => {
                my $archive-path = &temp-path() ~ '.zip';
                await powershell-client($zip-url, $archive-path);
                ok unzip-list($archive-path).result.first(*.ends-with('META6.json'));

                my $extract-to = &temp-path() andthen *.mkdir;
                await unzip-extract($archive-path, $extract-to);
                ok $extract-to.e;
                is $extract-to.dir.elems, 1;
                ok $extract-to.dir.first(*.d).child('META6.json').f;
            }
        }

        if has-tar() {
            subtest 'tar' => {
                my $archive-path = &temp-path() ~ '.tar.gz';
                await powershell-client($tar-url, $archive-path);
                ok tar-list($archive-path).result.first(*.ends-with('META6.json'));

                my $extract-to = &temp-path() andthen *.mkdir;
                await tar-extract($archive-path, $extract-to);
                ok $extract-to.e;
                is $extract-to.dir.elems, 1;
                ok $extract-to.dir.first(*.d).child('META6.json').f;
            }
        }

        if has-p5tar() {
            subtest 'p5tar' => {
                my $archive-path = &temp-path() ~ '.tar.gz';
                await powershell-client($tar-url, $archive-path);
                ok p5tar-list($archive-path).result.first(*.ends-with('META6.json'));

                my $extract-to = &temp-path() andthen *.mkdir;
                await p5tar-extract($archive-path, $extract-to);
                ok $extract-to.e;
                is $extract-to.dir.elems, 1;
                ok $extract-to.dir.first(*.d).child('META6.json').f;
            }
        }
    }
}


done-testing;
