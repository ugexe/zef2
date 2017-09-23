unit module Zef::Utils::IO;

use Zef::Utils::SystemCommands;
use Zef::Utils::FileSystem;

# todo: a more pluggable registry for system commands

our sub FETCH(*@_ [Str() $uri, IO() $save-to]) is export {
    die "target download directory {$save-to.parent} does not exist and could not be created"
        unless $save-to.parent.d || mkdir($save-to.parent);

    my $promise = do given $uri {
        when Zef::Uri::Git {
            proceed unless has-git();
            &Zef::Utils::SystemCommands::git-clone(|@_)
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
            &Zef::Utils::SystemCommands::powershell-client(|@_)          
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
        default {
            die "Failed to extract $archive to $extract-to";
        }
    }

    $promise.then: { $extract-to.e ?? $extract-to !! die($_) }
}

our sub LS-FILES(*@_ [IO() $path]) is export {
    die "target path $path does not exist"
        unless $path.e;

    my $promise = do given $path {
        when Zef::Uri::Git::Local {
            proceed unless has-git();
            &Zef::Utils::SystemCommands::git-ls-tree(|@_)
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
        default {
            die "Failed to determine a file listing from $path";
        }
    }

    return $promise;
}