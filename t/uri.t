use v6;
use Zef::Utils::FileSystem;
use Zef::URI;
use Test;

subtest 'sanity' => {
    ok temp-path().add('.git').mkdir.parent.absolute ~~ Zef::URI::Git::Local;
    ok 'https://github.com/ugexe/zef.git' ~~ Zef::URI::Git;
    ok 'https://github.com/ugexe/zef.git' ~~ Zef::URI::Http;
    ok 'https://github.com/ugexe/zef' !~~ Zef::URI::Git;
    ok 'https://github.com/ugexe/zef' ~~ Zef::URI::Http;
    ok '/foo/bar.tar.gz' ~~ Zef::URI::Tar;
    ok '/foo/bar.tgz' ~~ Zef::URI::Tar;
    ok '/foo/bar.zip' ~~ Zef::URI::Zip;
}

subtest 'http urls' => {
    my @uris =
        'http://p6.nu',
        'http://p6.nu/',
        'http://p6.nu/foo/bar',
        'http://p6.nu/foo/bar?baz=1',
        'http://p6.nu/foo/bar?baz=1&bar=2',
        'http://p6.nu/foo/bar?a=1&b=2#baz';

    for @uris -> $uri {
        ok $uri ~~ Zef::URI;
        ok $uri ~~ Zef::URI::Http;
    }
}

subtest 'Local paths' => {
    subtest 'Unixy' => {
        my @uris =
            '/my home/to/file',
            '../my home/to/file',
            './my home/to/file',
            './my home/to/../file';

        for @uris -> $uri {
            ok $uri ~~ Zef::URI;
        }
    }

    subtest 'Windowsy' => {
        my @uris =
            'C:\\my home\\to\\file',
            'C:\\..\\my home\\to\\file',
            'C:\\.\\my home\\to\\file',
            'C:\\.\\my home\\to\\..\\file';

        for @uris -> $uri {
            ok $uri ~~ Zef::URI;
        }
    }
}

subtest 'file:// local paths' => {
    subtest 'https://tools.ietf.org/html/rfc8089#page-18' => {
        subtest 'Local files' => {
            subtest 'A traditional file URI for a local file with an empty authority.' => {
                ok 'file:///path/to/file' ~~ Zef::URI;
            }

            subtest 'The minimal representation of a local file with no authority field and an absolute path that begins with a slash "/".' => {
                ok 'file:/path/to/file' ~~ Zef::URI;
            }

            subtest 'The minimal representation of a local file in a DOS- or Windows- based environment with no authority field and an absolute path that begins with a drive letter.' => {
                ok 'file:c:/path/to/file' ~~ Zef::URI;
            }

            subtest 'Regular DOS or Windows file URIs with vertical line characters in the drive letter construct.' => {
                for 'file:///c|/path/to/file', 'file:/c|/path/to/file', 'file:c|/path/to/file' -> $uri {
                    ok 'file:///path/to/file' ~~ Zef::URI;
                }
            }
        }

        subtest 'Non-local files' => {
            subtest 'The representation of a non-local file with an explicit authority.' => {
                ok 'file://host.example.com/path/to/file' ~~ Zef::URI;
            }

            subtest 'The "traditional" representation of a non-local file with an empty authority and a complete (transformed) UNC string in the path.' => {
                ok 'file:////host.example.com/path/to/file' ~~ Zef::URI;
            }

            subtest 'As above, with an extra slash between the empty authority and the transformed UNC string.' => {
                ok 'file://///host.example.com/path/to/file' ~~ Zef::URI;
            }
        }
    }
}


done-testing;
