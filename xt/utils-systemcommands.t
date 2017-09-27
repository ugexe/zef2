use v6;
use Zef::Utils::FileSystem;
use Zef::Utils::SystemCommands :ALL;
use Test;


my sub from-json($str) { Rakudo::Internals::JSON.from-json($str) }

my $http-url = 'https://httpbin.org/user-agent';
my $git-url  = 'git://github.com/ugexe/P6TCI.git';
my $tar-url  = 'https://github.com/ugexe/P6TCI/archive/master.tar.gz';
my $zip-url  = 'https://github.com/ugexe/P6TCI/archive/master.zip';

if has-git() {
    subtest 'git - basic' => {
        my $archive-path = temp-path(); # a directory, so don't add ext
        await git-download($git-url, $archive-path);
        ok $archive-path.child('META6.json').f;
        ok git-list-files($archive-path).result.first(*.ends-with('META6.json'));

        my $extract-to = temp-path() andthen *.mkdir;
        await git-extract($archive-path, $extract-to);
        ok $extract-to.e;
        is $extract-to.dir.elems, 1;
        ok $extract-to.dir.first(*.d).child('META6.json').f;
    }

    subtest 'git - specific revisions' => {
        my $rev1-sha1 = 'd2349d19404bbc9a5bc1e09c460b5c45af813799'; # META.info  / v0.0.4
        my $rev2-sha1 = 'de2637881b763094b3eebea713b076eac4e6316b'; # META6.json / v0.0.5
        my $git-url-rev1 = "https://github.com/ugexe/P6TCI.git@rev1-sha1";
        my $git-url-rev2 = "https://github.com/ugexe/P6TCI.git@$rev2-sha1";

        # This exists so FETCH can "download" a repo, which can later have
        # PATHS/EXTRACT called on it without keeping track of the revision.
        subtest 'pass/save revision to checkout in repo path - git-list-files(1)/git-extract(2)' => {
            my $archive-path-rev1 = temp-path("@$rev1-sha1");
            my $archive-path-rev2 = temp-path("@$rev2-sha1");
            ok git-download($git-url-rev1, $archive-path-rev1).result;
            ok git-download($git-url-rev2, $archive-path-rev2).result;

            my $extract-to-rev1 = temp-path() andthen *.mkdir;
            my $extract-to-rev2 = temp-path() andthen *.mkdir;

            ok git-list-files($archive-path-rev1).result.first(*.ends-with('META.info'));
            ok git-list-files($archive-path-rev2).result.first(*.ends-with('META6.json'));

            ok git-extract($archive-path-rev1, $extract-to-rev1).result;
            ok git-extract($archive-path-rev2, $extract-to-rev2).result;

            ok $extract-to-rev1.e;
            is $extract-to-rev1.dir.elems, 1;
            ok $extract-to-rev1.dir.first(*.d).child('META.info').f;
            nok $extract-to-rev1.dir.first(*.d).child('META6.json').f;
            is from-json($extract-to-rev1.dir.first(*.d).child('META.info').slurp)<version>, '0.0.4';

            ok $extract-to-rev2.e;
            is $extract-to-rev2.dir.elems, 1;
            ok $extract-to-rev2.dir.first(*.d).child('META6.json').f;
            nok $extract-to-rev2.dir.first(*.d).child('META.info').f;
            is from-json($extract-to-rev2.dir.first(*.d).child('META6.json').slurp)<version>, '0.0.5';
        }

        # ...although realistically it would be better if we could force passing around the revision explicitly
        # via git-list-files(3)/git-extract(3) instead of implicitly via paths as with git-list-files(2)/git-extract(2).
        subtest 'pass revision to checkout as parameter - git-list-files(2)/git-extract(3)' => {
            my $archive-path-rev1 = temp-path();
            my $archive-path-rev2 = temp-path();
            ok git-download($git-url-rev1, $archive-path-rev1).result;
            ok git-download($git-url-rev2, $archive-path-rev2).result;

            my $extract-to-rev1 = temp-path() andthen *.mkdir;
            my $extract-to-rev2 = temp-path() andthen *.mkdir;

            ok git-list-files($archive-path-rev1, $rev1-sha1).result.first(*.ends-with('META.info'));
            ok git-list-files($archive-path-rev2, $rev2-sha1).result.first(*.ends-with('META6.json'));

            ok git-extract($archive-path-rev1, $extract-to-rev1, $rev1-sha1).result;
            ok git-extract($archive-path-rev2, $extract-to-rev2, $rev2-sha1).result;

            ok $extract-to-rev1.e;
            is $extract-to-rev1.dir.elems, 1;
            ok $extract-to-rev1.dir.first(*.d).child('META.info').f;
            nok $extract-to-rev1.dir.first(*.d).child('META6.json').f;
            is from-json($extract-to-rev1.dir.first(*.d).child('META.info').slurp)<version>, '0.0.4';

            ok $extract-to-rev2.e;
            is $extract-to-rev2.dir.elems, 1;
            ok $extract-to-rev2.dir.first(*.d).child('META6.json').f;
            nok $extract-to-rev2.dir.first(*.d).child('META.info').f;
            is from-json($extract-to-rev2.dir.first(*.d).child('META6.json').slurp)<version>, '0.0.5';
        }
    }
}

if has-curl() && has-tar() && has-p5tar() {
    subtest 'curl / tar' => {
        subtest 'curl' => {
            my $path = temp-path('.json');
            ok curl($http-url, $path).so;
            ok $path.slurp.&from-json<user-agent> ~~ /:i rakudo/;
        }

        my $archive-path = temp-path('.tar.gz');
        await curl($tar-url, $archive-path);

        subtest 'tar' => {
            ok tar-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = temp-path() andthen *.mkdir;
            await tar-extract($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }

        subtest 'p5tar' => {
            ok p5tar-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = temp-path() andthen *.mkdir;
            await p5tar-extract($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }
    }
}

if has-wget() && has-unzip() {
    subtest 'wget / unzip' => {
        my $path = temp-path('.json');
        ok wget($http-url, $path).so;
        ok $path.slurp.&from-json<user-agent> ~~ /:i rakudo/;

        my $archive-path = temp-path('.zip');
        await wget($zip-url, $archive-path);

        subtest 'unzip' => {
            ok unzip-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = temp-path() andthen *.mkdir;
            await unzip-extract($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }
    }
}

if has-powershell() {
    subtest 'powershell' => {
        subtest 'powershell-download' => {
            my $path = temp-path('.json');
            ok powershell-download($http-url, $path).so;
            ok $path.slurp.&from-json<user-agent> ~~ /:i rakudo/;
        }

        subtest 'powershell-unzip' => {
            my $archive-path = temp-path('.zip');
            await powershell-download($zip-url, $archive-path);
            ok powershell-unzip-list($archive-path).result.first(*.ends-with('META6.json'));

            my $extract-to = temp-path() andthen *.mkdir;
            await powershell-unzip($archive-path, $extract-to);
            ok $extract-to.e;
            is $extract-to.dir.elems, 1;
            ok $extract-to.dir.first(*.d).child('META6.json').f;
        }

        if has-unzip() {
            subtest 'unzip' => {
                my $archive-path = temp-path('.zip');
                await powershell-download($zip-url, $archive-path);
                ok unzip-list($archive-path).result.first(*.ends-with('META6.json'));

                my $extract-to = temp-path() andthen *.mkdir;
                await unzip-extract($archive-path, $extract-to);
                ok $extract-to.e;
                is $extract-to.dir.elems, 1;
                ok $extract-to.dir.first(*.d).child('META6.json').f;
            }
        }

        if has-tar() {
            subtest 'tar' => {
                my $archive-path = temp-path('.tar.gz');
                await powershell-download($tar-url, $archive-path);
                ok tar-list($archive-path).result.first(*.ends-with('META6.json'));

                my $extract-to = temp-path() andthen *.mkdir;
                await tar-extract($archive-path, $extract-to);
                ok $extract-to.e;
                is $extract-to.dir.elems, 1;
                ok $extract-to.dir.first(*.d).child('META6.json').f;
            }
        }

        if has-p5tar() {
            subtest 'p5tar' => {
                my $archive-path = temp-path('.tar.gz');
                await powershell-download($tar-url, $archive-path);
                ok p5tar-list($archive-path).result.first(*.ends-with('META6.json'));

                my $extract-to = temp-path() andthen *.mkdir;
                await p5tar-extract($archive-path, $extract-to);
                ok $extract-to.e;
                is $extract-to.dir.elems, 1;
                ok $extract-to.dir.first(*.d).child('META6.json').f;
            }
        }
    }
}

if has-tput() {
    subtest 'tput' => {
        my $cols = tput-cols().result;
        ok $cols ~~ Int;
        ok $cols > -1;
    }
}

if has-mode() {
    subtest 'mode' => {
        my $cols = mode-cols().result;
        ok $cols ~~ Int;
        ok $cols > -1;
    }
}

done-testing;
