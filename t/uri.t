use v6;
use Zef::URI;
use Test;


subtest 'RFC3986' => {
    subtest 'URI' => {
        subtest 'URL' => {
            my $parser = Zef::IO::URI.new;
            ok so $parser.parse('http://p6.nu');
            ok so $parser.parse('http://p6.nu/');
            ok so $parser.parse('http://p6.nu/foo/bar');
            ok so $parser.parse('http://p6.nu/foo/bar?baz=1');
            ok so $parser.parse('http://p6.nu/foo/bar?baz=1&bar=2');
            ok so $parser.parse('http://p6.nu/foo/bar?a=1&b=2#baz');
        }
        # TODO: tests ( and parser logic ) for non-spec git uri formats
    }
    subtest 'URI-reference' => {
        subtest 'Unixy' => {
            my $parser = Zef::IO::URI.new;
            ok so $parser.parse('/my home/to/file'), 'basic absolute path';
            ok so $parser.parse('../my home/to/file'), 'basic relative path with ../';
            ok so $parser.parse('./my home/to/file'), 'basic relative path with ./';
            ok so $parser.parse('./my home/to/../file'), 'relative path with ./ and ../';
        }

        subtest 'Windowsy' => {
            my $parser = Zef::IO::URI.new;
            ok so $parser.parse('C:\\my home\\to\\file'), 'basic absolute path';
            ok so $parser.parse('C:\\..\\my home\\to\\file'), 'basic relative path with ../';
            ok so $parser.parse('C:\\.\\my home\\to\\file'), 'basic relative path with ./';
            ok so $parser.parse('C:\\.\\my home\\to\\..\\file'), 'relative path with ./ and ../';
        }
    }
}

subtest 'RFC8089' => {
    subtest 'https://tools.ietf.org/html/rfc8089#page-18' => {
        subtest 'Local files' => {
            subtest 'A traditional file URI for a local file with an empty authority.' => {
                my $parser = Zef::IO::URI.new;
                my $parsed = $parser.parse('file:///path/to/file');
                ok $parsed;
            }

            subtest 'The minimal representation of a local file with no authority field and an absolute path that begins with a slash "/".' => {
                my $parser = Zef::IO::URI.new;
                my $parsed = $parser.parse('file:/path/to/file');
                ok $parsed;
            }

            subtest 'The minimal representation of a local file in a DOS- or Windows- based environment with no authority field and an absolute path that begins with a drive letter.' => {
                my $parser = Zef::IO::URI.new;
                my $parsed = $parser.parse('file:c:/path/to/file');
                ok $parsed;
            }

            subtest 'Regular DOS or Windows file URIs with vertical line characters in the drive letter construct.' => {
                for 'file:///c|/path/to/file', 'file:/c|/path/to/file', 'file:c|/path/to/file' -> $uri {
                    my $parser = Zef::IO::URI.new;
                    my $parsed = $parser.parse('file:///path/to/file');
                    ok $parsed;
                }
            }
        }

        subtest 'Non-local files' => {
            subtest 'The representation of a non-local file with an explicit authority.' => {
                my $parser = Zef::IO::URI.new;
                my $parsed = $parser.parse('file://host.example.com/path/to/file');
                ok $parsed;
            }

            subtest 'The "traditional" representation of a non-local file with an empty authority and a complete (transformed) UNC string in the path.' => {
                my $parser = Zef::IO::URI.new;
                my $parsed = $parser.parse('file:////host.example.com/path/to/file');
                ok $parsed;
            }

            subtest 'As above, with an extra slash between the empty authority and the transformed UNC string.' => {
                my $parser = Zef::IO::URI.new;
                my $parsed = $parser.parse('file://///host.example.com/path/to/file');
                ok $parsed;
            }
        }
    }
}

done-testing;
