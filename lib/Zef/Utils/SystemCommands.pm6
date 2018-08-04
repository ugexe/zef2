unit module Zef::Utils::SystemCommands;
use Zef::Utils::FileSystem;
use Zef::URI;

# Provides thin wrappers around various system commands that are
# launched as an external process. It does not aim to provide a
# 1:1 implementation, but instead provides the required (small)
# subset of functionality to accomplish one of a few possible tasks.
# e.g. `git-clone` is not exported - instead `git-download` is provided
# which handles git uris with revisions/commits/tags (but has to use
# multiple commands)

# Basic usage info for ecosystem statistics
# XXX: spaces may break win32http.ps1 when launced via Proc::Async?
my $USERAGENT = "zef/{$*PERL.compiler}/{$*PERL.compiler.version}";

# Don't use this to launch anything with the perl6 command!
my sub proc(*@_ [$command, *@rest], *%_ [:CWD(:$cwd), :ENV(:%env), *%]) {
    my @invoke-with = (Zef::Utils::FileSystem::which($command).head // $command, |@rest);
    return Proc::Async.new(|@invoke-with);
}
my sub quiet-proc(*@_ [$, *@], *%_ [:CWD(:$cwd), :ENV(:%env), *%]) {
    with proc(|@_, |%_) {
        my $promise = Promise.new;
        react {
            whenever .stdout(:bin) { }
            whenever .stderr(:bin) { }
            whenever .start(|%_)   { .so ?? $promise.keep($_) !! $promise.break($_) }
        }
        return $promise;
    }
}


#
# Below are process spawning routines to do basic IO on the most common types of uris.
# Each base command has a `has-$name()` method that is cached after it's first execution
# at runtime. The base functionality of most routines if either FETCH, EXTRACT, or LS-FILES,
# although there are a few commands not related to those things (tput/mode etc). 
#
# These are intended to be used internally, but are exposed to give some build basics to simple
# native modules and one-liners. All methods are multis to make things a little more pluggable.
#


# [curl]
our sub has-curl is export { once { so try quiet-proc('curl', '--help').result } }

our proto sub curl(|) is export(:curl) {*}
multi sub curl(Zef::URI::Http:D $url, IO() $save-to) {
    my $cwd := $save-to.parent;
    return quiet-proc(:$cwd, 'curl', '--silent', '-L', '-A', $USERAGENT, '-z', $save-to.absolute, '-o', $save-to.absolute, $url);
}


# [wget]
our sub has-wget is export { once { try quiet-proc('wget', '--help').result.so } }

our proto sub wget(|) is export(:wget) {*}
multi sub wget(Zef::URI::Http:D $url, IO() $save-to) {
    my $cwd := $save-to.parent;
    return quiet-proc(:$cwd, 'wget', '-N', qq|--user-agent="{$USERAGENT}"|, '-P', $cwd, '--quiet', $url, '-O', $save-to.absolute);
}


# [unzip]
our sub has-unzip is export { once { so try quiet-proc('unzip', '--help').result } }

our proto sub unzip-extract(|) is export(:unzip) {*}
multi sub unzip-extract(IO() $archive-file, $extract-to) {
    my $cwd := $archive-file.parent;
    return quiet-proc(:$cwd, 'unzip', '-o', '-qq', $archive-file.basename, '-d', $extract-to.absolute);
}

our proto sub unzip-list(|) is export(:unzip) {*}
multi sub unzip-list(IO() $archive-file) {
    my $cwd := $archive-file.parent;

    with proc('unzip', '-Z', '-1', $archive-file.basename) {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start(:$cwd) { .so ?? $promise.keep($output.decode.lines) !! $promise.break($_) }
        }
        return $promise;
    }
}


# [tar]
our sub has-tar is export { once { so try quiet-proc('tar', '--help').result } }

our proto sub tar-extract(|) is export(:tar) {*}
multi sub tar-extract(IO() $archive-file, IO() $extract-to) {
    my $cwd := $archive-file.parent;
    return quiet-proc(:$cwd, 'tar', '-zxvf', $archive-file.basename, '-C', $extract-to.relative($cwd));
}

our proto sub tar-list(|) is export(:tar) {*}
multi sub tar-list(IO() $archive-file) {
    my $cwd := $archive-file.parent;

    with proc('tar', '--list', '-f', $archive-file.basename) {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start(:$cwd) { .so ?? $promise.keep($output.decode.lines) !! $promise.break($_) }
        }
        return $promise;
    }
}


# [perl5 + Archive::Tar]
our sub has-p5tar is export { once { so try quiet-proc('perl', '-MArchive::Tar', '-e0').result } }

our proto sub p5tar-extract(|) is export(:p5tar) {*}
multi sub p5tar-extract(IO() $archive-file, IO() $extract-to) {
    my $cwd := $extract-to;
    my $script = '
            use v5.10;
            use Archive::Tar;
            my $extractor = Archive::Tar->new();
            $extractor->read($ARGV[0]);
            $extractor->extract();
            exit 0;
        ';
    return quiet-proc(:$cwd, 'perl', '-e', $script, $archive-file.absolute);
}

our proto sub p5tar-list(|) is export(:p5tar) {*}
multi sub p5tar-list(IO() $archive-file) {
    my $cwd := $archive-file.parent;
    my $script = '
            use v5.10;
            use Archive::Tar;
            my $extractor = Archive::Tar->new();
            $extractor->read($ARGV[0]);
            print "$_\n" for( $extractor->list_files() );
            exit 0;
        ';

    with proc('perl', '-e', $script, $archive-file.basename) {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start(:$cwd) { .so ?? $promise.keep($output.decode.lines) !! $promise.break($_) }
        }
        return $promise;
    }
    return quiet-proc(:$cwd, 'perl', '-e', $script, $archive-file.basename);
}


# [git]
# TODO: the git-fu for most of these could be improved. FWIW these essentially treat each repo
# as a single revision, e.g. we make a new clone for any revision so that there is less chance
# the repo state gets changed unexpectedly (we really want shallow clones of specific commits I think?)
our sub has-git is export { once { so try quiet-proc('git', '--help').result } }
our sub git-repo-uri(Str() $uri) { with $uri.split(/\.git[\/]?/, :v) { .elems == 1 ?? ~$_ !! .elems == 2 ?? $_.join !! $_.head(*-1).join } }
our sub git-checkout-name(Str() $uri) { with $uri.split(/\.git[\/]?/, :v) { ~($_.tail.match(/\@(.*)[\/|\@|\?|\#]?/)[0] // 'HEAD') } }

# commands that get used for git-download, git-extract, git-list-files
my sub git-clone($url, IO() $save-to) {
    my $cwd := $save-to.parent;
    return quiet-proc(:$cwd, 'git', 'clone', $url, $save-to.basename, '--quiet');
}
my sub git-pull(IO() $repo-path) {
    my $cwd := $repo-path.absolute;
    return quiet-proc(:$cwd, 'git', 'pull', '--quiet');
}
my sub git-fetch(IO() $repo-path) {
    my $cwd := $repo-path.absolute;
    return quiet-proc(:$cwd, 'git', 'fetch', '--quiet');
}
my sub git-checkout(IO() $repo-path, IO() $extract-to, $id) {
    my $cwd := $repo-path.absolute;
    return quiet-proc(:$cwd, 'git', '--work-tree', $extract-to.absolute, 'checkout', $id, '.');
}
my sub git-rev-parse(IO() $repo-path) {
    my $cwd := $repo-path.absolute;
    with proc('git', 'rev-parse', git-checkout-name($repo-path)) {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start(:$cwd) { .so ?? $promise.keep($output.decode.lines.head) !! $promise.break($_) }
        }
        return $promise;
    }
}
my sub git-ls-tree(IO() $repo-path, $rev-sha1) {
    my $cwd := $repo-path.absolute;
    with proc('git', 'ls-tree', '-r', '--name-only', $rev-sha1) {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start(:$cwd) { .so ?? $promise.keep($output.decode.lines) !! $promise.break($_) }
        }
        return $promise;
    }
}

# The git-style interfaces we -do- provide makes some assumptions about what we want to do
# and is primarily so we can work with extended git urls that include commits/revisions.

# FETCH
our proto git-download(|) is export(:git) {*}
multi sub git-download(Zef::URI::Git:D $url, IO() $save-to, $sha1?) {
    await git-clone(git-repo-uri($url), $save-to);
    return git-fetch( $save-to );
}

# EXTRACT
our proto git-extract(|) is export(:git) {*}
multi sub git-extract(IO() $repo-path, IO() $extract-to) {
    my $sha1 = git-rev-parse( $repo-path ).result;
    samewith($repo-path, $extract-to, $sha1)
}
multi sub git-extract(IO() $repo-path, IO() $extract-to, $rev-sha1) {
    die "target repo directory {$repo-path.absolute} does not contain a .git/ folder"
        unless $repo-path.child('.git').d;

    await git-fetch( $repo-path );

    my $checkout-to = $extract-to.child($rev-sha1);
    die "target repo directory {$extract-to.absolute} does not exist and could not be created"
        unless ($checkout-to.e && $checkout-to.d) || mkdir($checkout-to);

    return git-checkout($repo-path, $checkout-to, $rev-sha1);
}

# LIST-FILES
our proto git-list-files(|) is export(:git) {*}
multi sub git-list-files(IO() $repo-path) {
    my $sha1 = git-rev-parse( $repo-path ).result;
    samewith($repo-path, $sha1)
}
multi sub git-list-files(IO() $repo-path, IO() $rev-sha1) {
    die "target repo directory {$repo-path.absolute} does not contain a .git/ folder"
        unless $repo-path.child('.git').d;

    await git-fetch( $repo-path );

    return git-ls-tree($repo-path, $rev-sha1);
}


# [powershell]
our sub has-powershell is export { once { so try quiet-proc('powershell', '-help').result } }

our proto sub powershell-download(|) is export(:powershell) {*}
multi sub powershell-download(Zef::URI::Http:D $url, IO() $save-to) {
    my $cwd := $save-to.parent;
    my $script = q<
            Param (
                [Parameter(Mandatory=$True)] [System.Uri]$uri,
                [Parameter(Mandatory=$True)] [string]$FilePath,
                [string]$UserAgent = 'rakudo perl6/zef powershell downloader'
            )

            $FilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)

            if ( -not (Test-Path $FilePath) ) {
                $client = New-Object System.Net.WebClient;
                $client.Headers['User-Agent'] = $UserAgent;
                $client.DownloadFile($uri.ToString(), $FilePath)
            } else {
                try {
                    $webRequest = [System.Net.HttpWebRequest]::Create($uri);
                    $webRequest.IfModifiedSince = ([System.IO.FileInfo]$FilePath).LastWriteTime
                    $webRequest.UserAgent = $UserAgent;
                    $webRequest.Method = 'GET';
                    [System.Net.HttpWebResponse]$webResponse = $webRequest.GetResponse()

                    $stream = New-Object System.IO.StreamReader($webResponse.GetResponseStream())
                    $stream.ReadToEnd() | Set-Content -Path $FilePath -Force
                } catch [System.Net.WebException] {
                    # If content isn't modified according to the output file timestamp then ignore the exception
                    if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotModified) {
                        throw $_
                    }
                }
            }
        >;
    return quiet-proc(:$cwd, 'powershell', '-NoProfile', '-ExecutionPolicy', 'unrestricted', 'Invoke-Command', '-ScriptBlock', '{'~$script~'}', '-ArgumentList', qq|"{$url}","{$save-to.absolute()}","{$USERAGENT}"|);
}

our proto sub powershell-unzip(|) is export(:powershell) {*}
multi sub powershell-unzip(IO() $archive-file, IO() $extract-to) {
    my $cwd := $archive-file.parent;
    my $script = q<
            Param (
                [Parameter(Mandatory=$True)] [string]$FilePath,
                [Parameter(Mandatory=$True)] [string]$out
            )
            $shell = New-Object -com shell.application
            $FilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
            $items = $shell.NameSpace($FilePath).items()
            $to = $shell.NameSpace($out)
            $to.CopyHere($items, 0x14)
        >;
    return quiet-proc(:$cwd, 'powershell', '-NoProfile', '-ExecutionPolicy', 'unrestricted', 'Invoke-Command', '-ScriptBlock', '{'~$script~'}', '-ArgumentList', qq|"{$archive-file.basename()}","{$extract-to.absolute()}"|);
}

our proto sub powershell-unzip-list(|) is export(:powershell) {*}
multi sub powershell-unzip-list(IO() $archive-file) {
    my $cwd := $archive-file.parent;
    my $script = q<
            Param (
                [Parameter(Mandatory=$True)] [string]$FilePath
            )
            $shell = New-Object -com shell.application
            $FilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
            $items = $shell.NameSpace($FilePath).items()

            function List-ZipFiles {
                $ns = $shell.NameSpace($args[0])
                foreach( $item in $ns.Items() ) {
                    if( $item.IsFolder ) {
                        List-ZipFiles($item)
                    } else {
                        $path = $item | Select -ExpandProperty Path
                        Write-Host $path
                    }
                }
            }

            $path = $items | Select -ExpandProperty Path
            Write-Host $path
            List-ZipFiles $path
        >;

    with proc('powershell', '-NoProfile', '-ExecutionPolicy', 'unrestricted', 'Invoke-Command', '-ScriptBlock', '{'~$script~'}', '-ArgumentList', qq|"$archive-file.absolute()"|) {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start(:$cwd) { .so ?? $promise.keep($output.decode.lines) !! $promise.break($_) }
        }
        return $promise;
    }
}


#
# Below are commands unrelated to FETCH/EXTRACT/PATH but useful none-the-less
#

# Basic cross-platformish "how many colums wide is the terminal" routine (mode on windows, tput otherwise)
our sub term-cols() is export { (BEGIN $*DISTRO.is-win) ?? mode-cols() !! tput-cols() }

# TODO: tput doesn't always give the right value - seems like `echo $COLUMNS` might be the better option except
# I don't think that gets updated when SIGWINCH is fired :(

# [tput]
our sub has-tput is export { once { so try quiet-proc('tput', '-V').result } }
our proto sub tput-cols(|) is export(:terminal) {*}
multi sub tput-cols() {
    with proc('tput', 'cols') {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start() { .so ?? $promise.keep(try +$output.decode('latin-1').lines.head) !! $promise.break($_) }
        }
        return $promise;
    }
}

# [mode]
our sub has-mode is export { once { so try quiet-proc('mode', '/?').result } }
our proto sub mode-cols(|) is export(:terminal) {*}
multi sub mode-cols() {
    with proc('mode') {
        my $promise = Promise.new;
        my $output = Buf.new;
        react {
            whenever .stdout(:bin) { $output.append($_) if .defined }
            whenever .stderr(:bin) { }
            whenever .start() {
                .not ?? $promise.break($_) !! do {
                    my $output-text = $output.decode('latin-1');
                    if $output-text ~~ /'CON:' \n <.ws> '-'+ \n .*? \n \N+? $<cols>=[<.digit>+]/ {
                        my $cols = $/<cols>.comb(/\d/).join;
                        try {+$cols} ?? $promise.keep($cols - 1) !! $promise.break("`mode-cols result wasn't a number: $cols");
                    }
                    else {
                        $promise.break("`mode-cols` gave unexpected output: $output-text");
                    }
                }
            }
        }
        return $promise;
    }
}
