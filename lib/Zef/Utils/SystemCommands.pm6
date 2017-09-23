unit module Zef::Utils::SystemCommands;


# Basic usage info for ecosystem statistics
# XXX: spaces break win32http.ps1 when launced via Proc::Async
my $USERAGENT = "zef/{$*PERL.compiler}/{$*PERL.compiler.version}";


# Some boilerplate for spawning processes
my sub proc(*@_ [$command, *@rest], *%_ [:CWD(:$cwd), :ENV(:%env), *%]) {
    my @invoke-with = (BEGIN $*DISTRO.is-win)
        ?? (which($command).head // $command, |@rest)
        !! @_;
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


# Define input in subtypes so our signatures do validation as well as advertise
# what type of input they take (e.g. avoid calling wget on Zef::Uri::Git urls)
# TODO: put this somewhere more centralized (maybe Zef.pm6, or a revamped Zef/URI.pm6)
# XXX: `of Cool` because it might be IO::Path or Str, and can't do `of IO()`
subset Zef::Uri::Git::Local of Cool where { .chars and $_.IO.child('.git').d }
subset Zef::Uri::Git of Cool where { .lc.starts-with('git://') or git-repo-uri($_).lc.ends-with('.git') }
subset Zef::Uri::Http of Cool where { .lc.starts-with('http://') or .lc.starts-with('https://') }
subset Zef::Uri::Tar of Cool where { .lc.ends-with('.tar.gz') or .lc.ends-with('.tgz') }
subset Zef::Uri::Zip of Cool where { .lc.ends-with('.zip') }


# [which] (currently only used for windows)
my sub which($name) {
    my $source-paths  := $*SPEC.path.grep(*.?chars).map(*.IO).grep(*.d);
    my $path-guesses  := $source-paths.map({ $_.child($name) });
    my $possibilities := $path-guesses.map: -> $path {
        ((BEGIN $*DISTRO.is-win)
            ?? ($path.absolute, %*ENV<PATHEXT>.split(';').map({ $path.absolute ~ $_ }).Slip)
            !! $path.absolute).Slip
    }

    return $possibilities.grep(*.defined).grep(*.IO.f);
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
multi sub curl(Zef::Uri::Http:D $url, IO() $save-to) {
    my $cwd := $save-to.parent;
    return quiet-proc(:$cwd, 'curl', '--silent', '-L', '-A', $USERAGENT, '-z', $save-to.absolute, '-o', $save-to.absolute, $url);
}


# [wget]
our sub has-wget is export { once { try quiet-proc('wget', '--help').result.so } }

our proto sub wget(|) is export(:wget) {*}
multi sub wget(Zef::Uri::Http:D $url, IO() $save-to) {
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
our sub has-git is export { once { so try quiet-proc('git', '--help').result } }
sub git-repo-uri(Str() $uri) { with $uri.split(/\.git[\/]?/, :v) { .elems == 1 ?? ~$_ !! .elems == 2 ?? $_.join !! $_.head(*-1).join } }
sub git-checkout-name(Str() $uri) { with $uri.split(/\.git[\/]?/, :v) { ~($_.tail.match(/\@(.*)[\/|\@|\?|\#]?/)[0] // 'HEAD') } }

our proto sub git-clone(|) is export(:git) {*}
multi sub git-clone(Zef::Uri::Git:D $url, IO() $save-to) {
    my $cwd := $save-to.parent;
    return quiet-proc(:$cwd, 'git', 'clone', git-repo-uri( $url ), $save-to.basename, '--quiet');
}

our proto sub git-pull(|) is export(:git) {*}
multi sub git-pull(IO() $repo-path) {
    my $cwd := $repo-path.absolute;
    return quiet-proc(:$cwd, 'git', 'pull', '--quiet');
}

our proto sub git-fetch(|) is export(:git) {*}
multi sub git-fetch(IO() $repo-path) {
    my $cwd := $repo-path.absolute;
    return quiet-proc(:$cwd, 'git', 'fetch', '--quiet');
}

our proto sub git-checkout(|) is export(:git) {*}
multi sub git-checkout(IO() $repo-path, IO() $extract-to, $id) {
    my $cwd := $repo-path.absolute;
    return quiet-proc(:$cwd, 'git', '--work-tree', $extract-to.absolute, 'checkout', $id, '.');
}

our proto sub git-rev-parse(|) is export(:git) {*}
multi sub git-rev-parse(IO() $repo-path) {
    my $cwd := $repo-path.absolute;

    with proc('git', 'rev-parse', git-checkout-name($repo-path)) {
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

our proto sub git-ls-tree(|) is export(:git) {*}
multi sub git-ls-tree(IO() $repo-path) {
    my $cwd := $repo-path.absolute;

    with proc('git', 'ls-tree', '-r', '--name-only', git-checkout-name($repo-path)) {
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

# combines the git commands to do what we consider an extract
our proto git-extract(|) is export(:git) {*}
multi sub git-extract(IO() $repo-path, IO() $extract-to, $sha1?) {
    die "target repo directory {$repo-path.absolute} does not contain a .git/ folder"
        unless $repo-path.child('.git').d;

    await git-fetch( $repo-path );

    my $rev-sha1 = $sha1 // git-rev-parse( $repo-path ).result.head;
    my $checkout-to = $extract-to.child($rev-sha1);
    die "target repo directory {$extract-to.absolute} does not exist and could not be created"
        unless ($checkout-to.e && $checkout-to.d) || mkdir($checkout-to);

    return git-checkout($repo-path, $checkout-to, $rev-sha1);
}


# [powershell]
our sub has-powershell is export { once { so try quiet-proc('powershell', '-help').result } }

our proto sub powershell-client(|) is export(:powershell) {*}
multi sub powershell-client(Zef::Uri::Http:D $url, IO() $save-to) {
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

our proto sub powershell-unzip(|)  is export(:powershell) {*}
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
