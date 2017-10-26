unit module Zef::Utils::IO;

use Zef::Utils::SystemCommands;
use Zef::Utils::FileSystem;
use Zef::Utils::URI;

# Provides the heuristic based build routines zef uses internally.
# Previously this was done inside a factory class/plugin, but for
# non-internal use (such as a Build.pm that just wants to fetch or
# extract some files with little/no dependencies) required some
# config setup.
#
# The Zef::Utils::FileSystem codepaths are technically redundant - FETCH/EXTRACT
# on a path would just copy it twice. Internally elsewhere we would check first
# if we -need- to fetch or extract something because calling them. This allows
# the simple FETCH/EXTRACT/PATH api to remain consistent in acting like an IO::Any.

our sub FETCH(*@_ [Str() $uri, IO() $save-to]) is export {
    die "target download directory {$save-to.parent} does not exist and could not be created"
        unless $save-to.parent.d || mkdir($save-to.parent);

    my $promise = do given $uri {
        when Zef::Uri::Git {
            proceed unless has-git();
            &Zef::Utils::SystemCommands::git-download(|@_)
        }
        when Zef::Uri::Http {
            proceed unless has-curl();
            &Zef::Utils::SystemCommands::curl(|@_)
        }
        when Zef::Uri::Http {
            proceed unless has-wget();
            &Zef::Utils::SystemCommands::wget(|@_)
        }
        when Zef::Uri::Http {
            proceed unless has-powershell();
            &Zef::Utils::SystemCommands::powershell-download(|@_)
        }
        when *.IO.e {
            start { copy-paths(|@_) }
        }
        default {
            die "Don't know how to fetch $uri";
        }
    }

    $promise.then: { $save-to.e ?? $save-to !! die($_) }
}

our sub EXTRACT(*@_ [IO() $archive, IO() $extract-to]) is export {
    die "target archive path $archive does not exist"
        unless $archive.e || mkdir($archive);
    die "target extraction directory $extract-to does not exist and could not be created"
        unless $extract-to.d || mkdir($extract-to);

    my $promise = do given $archive {
        when Zef::Uri::Git::Local {
            proceed unless has-git();
            &Zef::Utils::SystemCommands::git-extract(|@_)
        }
        when Zef::Uri::Tar {
            proceed unless has-tar();
            &Zef::Utils::SystemCommands::tar-extract(|@_)
        }
        when Zef::Uri::Tar {
            proceed unless has-p5tar();
            &Zef::Utils::SystemCommands::p5tar-extract(|@_)
        }
        when Zef::Uri::Zip {
            proceed unless has-unzip();
            &Zef::Utils::SystemCommands::unzip-extract(|@_)
        }
        when Zef::Uri::Zip {
            proceed unless has-powershell();
            &Zef::Utils::SystemCommands::powershell-unzip(|@_)
        }
        when *.IO.e {
            start { copy-paths(|@_) }
        }
        default {
            die "Failed to extract $archive to $extract-to";
        }
    }

    $promise.then: { $extract-to.e ?? $extract-to !! die($_) }
}

our sub PATHS(*@_ [IO() $path]) is export {
    die "target path $path does not exist"
        unless $path.e;

    my $promise = do given $path {
        when Zef::Uri::Git::Local {
            proceed unless has-git();
            &Zef::Utils::SystemCommands::git-list-files(|@_)
        }
        when Zef::Uri::Tar {
            proceed unless has-tar();
            &Zef::Utils::SystemCommands::tar-list(|@_)
        }
        when Zef::Uri::Tar {
            proceed unless has-p5tar();
            &Zef::Utils::SystemCommands::p5tar-list(|@_)
        }
        when Zef::Uri::Zip {
            proceed unless has-unzip();
            &Zef::Utils::SystemCommands::unzip-list(|@_)
        }
        when Zef::Uri::Zip {
            proceed unless has-powershell();
            &Zef::Utils::SystemCommands::powershell-unzip-list(|@_)
        }
        when *.IO.e {
            start { list-paths(|@_) }
        }
        default {
            die "Failed to determine a file listing from $path";
        }
    }

    return $promise;
}

