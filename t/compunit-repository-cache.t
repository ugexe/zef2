use v6;
use Zef::Utils::FileSystem;
use CompUnit::Repository::Cache;
use Zef::Distribution;
use Test;


my sub gen-dist-files(*%d) {
    my &to-json := -> $o { Rakudo::Internals::JSON.to-json($o) }
    my $dist-dir = Zef::Utils::FileSystem::temp-path() andthen *.mkdir;
    $dist-dir.IO.child('META6.json').spurt(to-json(%d));
    for %d<provides> {
        my $to = $dist-dir.IO.child(.value) andthen {.parent.mkdir unless .parent.e}
        $to.spurt: (qq|unit module {.key};\n| ~ q|sub source-file is export {$?FILE}|);
    }
    return $dist-dir.IO;
}

my sub dependencyspecification(%_) {
    CompUnit::DependencySpecification.new(
        short-name      => %_<name>,
        auth-matcher    => %_<auth>                    // True,
        version-matcher => %_<ver version>.first(*.so) // True,
        api-matcher     => %_<api>                     // True,
    )
}


subtest 'Installing' => {
    my $dist-dir = gen-dist-files(:perl<6.c>, :name<XXX>, :ver<1>, :provides(:XXX<lib/XXX.pm6>));
    my $dist     = Zef::Distribution::FileSystem.new(prefix => $dist-dir);
    my $cuspec   = dependencyspecification($dist.meta.hash);
    my $cur      = CompUnit::Repository::Cache.new(prefix => temp-path().absolute);

    ok $cur;
    is $cur.candidates($cuspec).elems, 0;
    is $cur.installed.elems, 0;
    ok $cur.install($dist);
    is $cur.candidates($cuspec).elems, 1;
    is $cur.installed.elems, 1;
    ok $cur.uninstall($dist);
    is $cur.candidates($cuspec).elems, 0;
    is $cur.installed.elems, 0;
}

subtest 'Querying' => {
    my $dist1-dir = gen-dist-files(:perl<6.c>, :name<XXX>, :ver<1>, :api<1>, :auth<foo>, :provides(:XXX<lib/XXX.pm6>));
    my $dist2-dir = gen-dist-files(:perl<6.c>, :name<XXX>, :ver<1>, :api<2>, :auth<bar>, :provides(:XXX<lib/XXX.pm6>));
    my $dist1     = Zef::Distribution::FileSystem.new(prefix => $dist1-dir);
    my $dist2     = Zef::Distribution::FileSystem.new(prefix => $dist2-dir);
    my $cuspec1   = dependencyspecification($dist1.meta.hash);
    my $cuspec2   = dependencyspecification($dist2.meta.hash);
    my $cur       = CompUnit::Repository::Cache.new(prefix => temp-path().absolute);

    subtest 'sanity' => {
        ok $cur;
        is $cur.candidates($cuspec1).elems, 0;
        is $cur.candidates($cuspec2).elems, 0;
        is $cur.installed.elems, 0;
    }

    # XXX:auth<foo>:api<1>
    ok $cur.install($dist1);
    is $cur.candidates($cuspec1).elems, 1;
    is $cur.candidates($cuspec2).elems, 0;
    is $cur.installed.elems, 1;
    is $cur.candidates(dependencyspecification(%( :name<XXX>, :api<1> ))).elems, 1;

    # XXX:auth<bar>:api<2>
    ok $cur.install($dist2);
    is $cur.candidates($cuspec1).elems, 1;
    is $cur.candidates($cuspec2).elems, 1;
    is $cur.installed.elems, 2;
    is $cur.candidates(dependencyspecification(%( :name<XXX>, :api<2> ))).elems, 1;

    # xxx: makes sure :api querying works, show the loading failures TODO'd later are caused by rakudo not handling :api yet
    isnt $cur.candidates(dependencyspecification(%( :name<XXX>, :api<1> ))).head.meta<api>, $cur.candidates(dependencyspecification(%( :name<XXX>, :api<2> ))).head.meta<api>;
    nok $cur.candidates(dependencyspecification(%( :name<XXX>, :api<1> ))).head eqv $cur.candidates(dependencyspecification(%( :name<XXX>, :api<2> ))).head;

    # handle search for `XXX` (e.g. not explicitly XXX:auth<foo> or XXX:auth<bar>)
    my $cuspec-any-auth = dependencyspecification(%( :name<XXX> ));
    is $cur.candidates($cuspec-any-auth).elems, 2;

    # uninstall dist 1 of 2: XXX:auth<foo>
    ok $cur.uninstall($dist1);
    is $cur.candidates($cuspec1).elems, 0;
    is $cur.candidates($cuspec2).elems, 1;
    is $cur.installed.elems, 1;

    # uninstall dist 2 of 2: XXX:auth<bar>
    ok $cur.uninstall($dist2);
    is $cur.candidates($cuspec1).elems, 0;
    is $cur.candidates($cuspec2).elems, 0;
    is $cur.installed.elems, 0;
}


subtest 'Loading' => {
    my $dist1-dir = gen-dist-files(:perl<6.c>, :name<XXX>, :ver<1>, :api<1>, :auth<foo>, :provides(:XXX<lib/XXX.pm6>));
    my $dist2-dir = gen-dist-files(:perl<6.c>, :name<XXX>, :ver<2>, :api<2>, :auth<bar>, :provides(:XXX<lib/XXX.pm6>));
    my $dist1     = Zef::Distribution::FileSystem.new(prefix => $dist1-dir);
    my $dist2     = Zef::Distribution::FileSystem.new(prefix => $dist2-dir);
    my $cuspec1   = dependencyspecification($dist1.meta.hash);
    my $cuspec2   = dependencyspecification($dist2.meta.hash);
    my $cur       = CompUnit::Repository::Cache.new(prefix => temp-path().absolute);

    subtest 'sanity' => {
        ok $cur;
        is $cur.candidates($cuspec1).elems, 0;
        is $cur.candidates($cuspec2).elems, 0;
        is $cur.installed.elems, 0;
    }

    ok $cur.install($dist1);
    is $cur.installed.elems, 1;
    ok $cur.install($dist2);
    is $cur.installed.elems, 2;

    my $eval-to-load-cache = qq|use CompUnit::Repository::Cache; use lib "CompUnit::Repository::Cache#{$cur.prefix.IO.absolute}"; |;

    subtest 'require XXX' => {
        # require XXX
        my $eval-to-load-by-name = $eval-to-load-cache ~ q|require XXX <&source-file>; &source-file().IO.absolute|;
        eval-lives-ok $eval-to-load-by-name;
        my $name-source-file = EVAL $eval-to-load-by-name;
        $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
        ok $name-source-file.IO.e;
    }

    subtest 'use XXX' => {
        # use XXX
        my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX; source-file().IO.absolute|;
        eval-lives-ok $eval-to-load-by-name;
        my $name-source-file = EVAL $eval-to-load-by-name;
        $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
        ok $name-source-file.IO.e;
    }

    subtest 'use - explicit' => {
        subtest 'ver' => {
            my $ver1-source-file;
            my $ver2-source-file;

            subtest 'XXX:ver<1>' => {
                my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:ver<1>; source-file().IO.absolute|;
                eval-lives-ok $eval-to-load-by-name;
                my $name-source-file = EVAL $eval-to-load-by-name;
                $ver1-source-file = $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                ok $ver1-source-file.IO.e;
            }

            subtest 'XXX:ver<2>' => {
                my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:ver<2>; source-file().IO.absolute|;
                eval-lives-ok $eval-to-load-by-name;
                my $name-source-file = EVAL $eval-to-load-by-name;
                $ver2-source-file = $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                ok $ver2-source-file.IO.e;
            }

            isnt $ver1-source-file, $ver2-source-file;

            subtest 'use XXX:ver<1.1+>' => {
                my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:ver<1.1+>; source-file().IO.absolute|;
                eval-lives-ok $eval-to-load-by-name;
                my $name-source-file = EVAL $eval-to-load-by-name;
                $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                ok $name-source-file.IO.e;

                isnt $name-source-file, $ver1-source-file;
                is $name-source-file, $ver2-source-file;
            }
        }

        subtest 'api' => {
            my $api1-source-file;
            my $api2-source-file;

            subtest 'XXX:api<1>' => {
                my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:api<1>; source-file().IO.absolute|;
                eval-lives-ok $eval-to-load-by-name;
                my $name-source-file = EVAL $eval-to-load-by-name;
                $api1-source-file = $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                ok $api1-source-file.IO.e;
            }

            # TODO: This doesn't work for some reason. I suspect something precomp related doesn't handle :api yet
            # since an earlier test on .candidates handles differing api versions ok.
            if 0 {
                subtest 'XXX:api<2>' => {
                    my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:api<2>; source-file().IO.absolute|;
                    eval-lives-ok $eval-to-load-by-name;
                    my $name-source-file = EVAL $eval-to-load-by-name;
                    $api2-source-file = $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                    ok $api2-source-file.IO.e;
                }

                isnt $api1-source-file, $api2-source-file;

                subtest 'use XXX:api<1.1+>' => {
                    my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:api<1.1+>; source-file().IO.absolute|;
                    eval-lives-ok $eval-to-load-by-name;
                    my $name-source-file = EVAL $eval-to-load-by-name;
                    $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                    ok $name-source-file.IO.e;

                    isnt $name-source-file, $api1-source-file;
                    is $name-source-file, $api2-source-file;
                }
            }
        }

        subtest 'auth' => {
            my $auth1-source-file;
            my $auth2-source-file;

            subtest 'XXX:auth<foo>' => {
                my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:api<foo>; source-file().IO.absolute|;
                eval-lives-ok $eval-to-load-by-name;
                my $name-source-file = EVAL $eval-to-load-by-name;
                $auth1-source-file = $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                ok $auth1-source-file.IO.e;
            }

            subtest 'XXX:auth<bar>' => {
                my $eval-to-load-by-name = $eval-to-load-cache ~ q|use XXX:auth<bar>; source-file().IO.absolute|;
                eval-lives-ok $eval-to-load-by-name;
                my $name-source-file = EVAL $eval-to-load-by-name;
                $auth2-source-file = $name-source-file .= subst(/\s\(.*?\)$/, ''); # workaround precomp $?FILE issue
                ok $auth2-source-file.IO.e;
            }

            isnt $auth1-source-file, $auth2-source-file;
        }
    }
}


done-testing;
