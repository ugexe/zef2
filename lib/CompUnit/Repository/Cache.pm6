# Like CUR::FileSystem but CUR::Installable
# e.g. copy default layout into some prefix (a sha1 of the module right now) and add CURI methods to access it

# TODO:
# Improve findability of "installed" modules by putting the sha1 directory into a parent that contains the module name
#
# CHANGE THIS FORMAT -
# prefix/
# prefix/sha1-of-module1-ver1/
# prefix/sha1-of-module1-ver1/META6.json
# prefix/sha1-of-module2-ver9/
# prefix/sha1-of-module2/-ver9/META6.json
#
# TO THIS FORMAT -
# prefix/
# prefix/module1/sha1-of-module1-ver1/
# prefix/module1/sha1-of-module1-ver1/META6.json
# prefix/module2/sha1-of-module2-ver9/
# prefix/module2/sha1-of-module2-ver9/META6.json

# TODO: encode unsafe file names

# TODO: method load (for `require $path`)

class CompUnit::Repository::Cache {
    also does CompUnit::Repository::Installable;
    also does CompUnit::Repository::Locally;

    has %!loaded; # cache compunit lookup for self.need(...)
    has %!seen;   # cache distribution lookup for self!matching-dist(...)
    has $!name;

    has $!precomp;
    has $!precomp-stores;
    has $!precomp-store;

    # Any given distribution/cur will have an understanding of the meta format
    # it accepts. Some leaf nodes may be changed such that the original -string-
    # value is change into the single key to a hash with some arbitrary value.
    # e.g. CURFS modified 'lib/Foo.pm6' to {'lib/Foo.pm6' => {'file' => '23f9jfaf3faij', 'time' => 'xxx', ...}}
    # It could also be used to extend other fields, such as resources, so one could add various traits/meta-data
    # that can easily be ignored while still understanding the format (by this routine).
    my sub parse-value($str-or-kv) {
        do given $str-or-kv {
            when Str  { $_ }
            when Hash { $_.keys[0] }
            when Pair { $_.key     }
        }
    }

    my sub sha1(*@_) { use nqp; reduce { nqp::sha1($^a, $^b) }, @_ }

    submethod BUILD(:$!prefix, :$!lock, :$!WHICH, :$!next-repo, Str :$!name = 'cache' --> Nil) {
        CompUnit::RepositoryRegistry.register-name($!name, self);
    }

    method installed(--> Seq) {
        return ().Seq unless self.prefix.e && self.prefix.d;
        my $dist-dirs := self.prefix.dir.grep(*.d).grep(*.child('META6.json').e);
        return $dist-dirs.map: { self!read-dist($_.basename) }
    }

    proto method files(|) {*}
    multi method files($file, Str:D :$name!, :$auth, :$ver, :$api) {
        my $spec = CompUnit::DependencySpecification.new(
            short-name      => $name,
            auth-matcher    => $auth // True,
            version-matcher => $ver  // True,
            api-matcher     => $api  // True,
        );

        with self.candidates($spec) {
            my $matches := $_.grep: { .meta<files>{$file}:exists }

            my $absolutified-metas := $matches.map: {
                my $meta      = $_.meta;
                $meta<source> = $meta<files>{$file}.IO;
                $meta;
            }

            return $absolutified-metas.grep(*.<source>.e);
        }
    }
    multi method files($file, :$auth, :$ver, :$api) {
        my $spec = CompUnit::DependencySpecification.new(
            short-name      => $file,
            auth-matcher    => $auth // True,
            version-matcher => $ver  // True,
            api-matcher     => $api  // True,
        );

        with self.candidates($spec) {
            my $absolutified-metas := $_.map: {
                my $meta      = $_.meta;
                $meta<source> = $meta<files>{$file}.IO;
                $meta;
            }

            return $absolutified-metas.grep(*.<source>.e);
        }
    }

    proto method candidates(|) {*}
    multi method candidates(Str:D $name, :$auth, :$ver, :$api) {
        return samewith(CompUnit::DependencySpecification.new(
            short-name      => $name,
            auth-matcher    => $auth // True,
            version-matcher => $ver  // True,
            api-matcher     => $api  // True,
        ));
    }
    multi method candidates(CompUnit::DependencySpecification $spec) {
        return Empty unless $spec.from eq 'Perl6';

        my $version-matcher = ($spec.version-matcher ~~ Bool)
            ?? $spec.version-matcher
            !! Version.new($spec.version-matcher);
        my $api-matcher = ($spec.api-matcher ~~ Bool)
            ?? $spec.api-matcher
            !! Version.new($spec.api-matcher);

        my $matching-dists := self.installed.grep: {
            my $name-matcher = any(
                $_.meta<name>,
                |$_.meta<provides>.keys,
                |$_.meta<provides>.values.map(*.&parse-value),
                |$_.meta<files>.hash.keys,
            );

            if $_.meta<provides>{$spec.short-name}
            // $_.meta<files>{$spec.short-name} -> $source
            {
                $_.meta<source> = $_.prefix.child(parse-value($source)).absolute;
            }

            so $spec.short-name eq $name-matcher
                and $_.meta<auth> ~~ $spec.auth-matcher
                and Version.new($_.meta<ver>) ~~ $version-matcher
                and Version.new($_.meta<api>) ~~ $api-matcher
        }

        return $matching-dists;
    }

    method !matching-dist(CompUnit::DependencySpecification $spec) {
        return %!seen{~$spec} if %!seen{~$spec}:exists;

        my $dist = self.candidates($spec).head;

        $!lock.protect: {
            return %!seen{~$spec} //= $dist;
        }
    }

    method loaded(--> Iterable:D)  { %!loaded.values }
    method prefix(--> IO::Path:D)  { $!prefix.IO }
    method name(--> Str:D)         { $!name }
    method short-id(--> Str:D)     { 'cache' }
    method id(--> Str:D)           { sha1(self.installed.map(*.id).sort) }
    method path-spec(--> Str:D)    { "CompUnit::Repository::Cache#name({$!name // 'cache'})#{self.prefix.absolute}" }
    method can-install(--> Bool:D) { $.prefix.w || ?(!$.prefix.e && try { $.prefix.mkdir } && $.prefix.e) }

    method !content-address($distribution, $name-path) { sha1($name-path, $distribution.id) }
    method !read-dist($dist-id) {
        my role CacheId { has $.id }
        Distribution::Path.new(self.prefix.child($dist-id)) but CacheId($dist-id);
    }

    method need(
        CompUnit::DependencySpecification  $spec,
        CompUnit::PrecompilationRepository $precomp        = self.precomp-repository(),
        CompUnit::PrecompilationStore     :@precomp-stores = self!precomp-stores(),
        --> CompUnit:D)
    {
        $*RAKUDO_MODULE_DEBUG("[need] -> {$spec.perl}") if $*RAKUDO_MODULE_DEBUG;
        return %!loaded{~$spec} if %!loaded{~$spec}:exists;

        with self!matching-dist($spec) {
            my $id = self!content-address($_, $spec.short-name);
            return %!loaded{$id} if %!loaded{$id}:exists;

            X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw
                unless .meta<source>;

            my $name-path     = parse-value($_.meta<provides>{$spec.short-name});
            my $source-path   = $_.meta<source>.IO;
            my $source-handle = CompUnit::Loader.load-source-file($source-path);

            $*RAKUDO_MODULE_DEBUG("[need] name-path:{$name-path}=$source-path source-handle:{$source-handle.perl}") if $*RAKUDO_MODULE_DEBUG;

            my $*RESOURCES = Distribution::Resources.new(:repo(self), :dist-id($_.id));
            my $precomp-handle = $precomp.try-load(
                CompUnit::PrecompilationDependency::File.new(
                    id       => CompUnit::PrecompilationId.new($id),
                    src      => $source-path.absolute,
                    checksum => ($_.meta<checksum>:exists ?? $_.meta<checksum> !! Str),
                    spec     => $spec,
                ),
                :source($source-path),
                :@precomp-stores,
            );
            my $compunit = CompUnit.new(
                handle       => ($precomp-handle // $source-handle),
                short-name   => $spec.short-name,
                version      => Version.new($_.meta<ver>),
                auth         => ($_.meta<auth> // Str),
                repo         => self,
                repo-id      => $id,
                precompiled  => $precomp-handle.defined,
                distribution => $_,
            );

            return %!loaded{~$spec} //= $compunit;
        }

        return self.next-repo.need($spec, $precomp, :@precomp-stores) if self.next-repo;
        X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw;
    }

    method resolve(CompUnit::DependencySpecification $spec --> CompUnit:D) {
        with self!matching-dist($spec) {
            return CompUnit.new(
                :handle(CompUnit::Handle),
                :short-name($spec.short-name),
                :version(Version.new($_.meta<ver>)),
                :auth($_.meta<auth> // Str),
                :repo(self),
                :repo-id(self!content-address($_, $spec.short-name)),
                :distribution($_),
            );
        }

        return self.next-repo.resolve($spec) if self.next-repo;
        Nil
    }


    method resource($dist-id, $key --> IO::Path) {
        self.prefix.child($dist-id).child("$key");
    }

    method uninstall(Distribution $distribution) {
        my $dist      = CompUnit::Repository::Distribution.new($distribution);
        my $dist-dir  = self.prefix.child($dist.id);

        my &unlink-if-exists := -> $path {
                $path.IO.d ?? (try { rmdir($path)  }) 
            !!  $path.IO.f ?? (try { unlink($path) })
            !! False
        }

        my &recursively-delete-empty-dirs := -> @_ {
            my @dirs = @_.grep(*.IO.d).map(*.&dir).map(*.Slip);
            &?BLOCK(@dirs) if +@dirs;
            unlink-if-exists( $_ ) for @dirs;
        }

        # special directory files
        for $dist.meta<files>.hash.kv -> $name-path, $file {
            if $name-path.starts-with('bin/') && self.files($name-path).elems {
                recursively-delete-empty-dirs([ self.prefix.child('bin') ]);
                unlink-if-exists( self.prefix.child('bin/') );
            }

            # distribution's bin/ and resources/
            unlink-if-exists( $dist-dir.child($name-path.IO.parent).child($file.IO.basename) );
        }

        # module/lib files
        for $dist.meta<provides>.hash.values.map(*.&parse-value) -> $name-path {
            unlink-if-exists( $dist-dir.child($name-path) );
        }

        # meta
        unlink-if-exists( $dist-dir.child("META6.json") );

        # delete remaining empty directories recursively
        recursively-delete-empty-dirs([$dist-dir]);
        unlink-if-exists( $dist-dir );
    }

    method install(Distribution $distribution, Bool :$force, Bool :$precompile = False) {
        my $dist = CompUnit::Repository::Distribution.new($distribution);
        fail "$dist already installed" if not $force and $dist.id ~~ self.installed.map(*.id).any;

        $!lock.protect: {
            my @*MODULES;
            my $dist-dir = self.prefix.child($dist.id) andthen *.mkdir;
            my $is-win   = Rakudo::Internals.IS-WIN;

            my $implicit-files := $dist.meta<provides>.values;
            my $explicit-files := $dist.meta<files>;
            my $all-files      := unique map { $_ ~~ Str ?? $_ !! $_.keys[0] },
                grep *.defined, $implicit-files.Slip, $explicit-files.Slip;

            for @$all-files -> $name-path {
                state %pm6-path2name = $dist.meta<provides>.antipairs;
                state @provides      = $dist.meta<provides>.values;

                given $name-path {
                    my $handle := $dist.content($name-path);
                    my $destination = $dist-dir.child($name-path) andthen *.parent.mkdir;

                    when /^@provides$/ {
                        my $name = %pm6-path2name{$name-path};
                        note("Installing {$name} for {$dist.meta<name>}") if %*ENV<RAKUDO_LOG_PRECOMP> and $name ne $dist.meta<name>;
                        $destination.spurt( $handle.open(:bin).slurp(:close) );
                    }

                    when /^bin\// {
                        my $name = $name-path.subst(/^bin\//, '');
                        $destination.spurt( $handle.open(:bin).slurp(:close) );
                    }

                    when /^resources\/$<subdir>=(.*)/ {
                        my $subdir = $<subdir>; # maybe do something with libraries
                        $destination.spurt( $handle.open(:bin).slurp(:close) );
                    }
                }
            }

            spurt( $dist-dir.child('META6.json').absolute, Rakudo::Internals::JSON.to-json($dist.meta.hash) );
            self!precompile-distribution-by-id($dist.id) if ?$precompile;
            return $dist;
        }
    }


    ### Precomp stuff beyond this point

   method !precompile-distribution-by-id($dist-id --> Bool:D) {
        my $dist         = self!read-dist($dist-id);
        my $precomp-repo = self.precomp-repository;

        $!lock.protect: {
            for $dist.meta<provides>.hash.kv -> $name, $name-path {
                state $compiler-id = CompUnit::PrecompilationId.new($*PERL.compiler.id);
                my $precomp-id     = CompUnit::PrecompilationId.new(self!content-address($dist, $name-path));
                $precomp-repo.store.delete($compiler-id, $precomp-id);
            }

            {
                ENTER my $head = $*REPO;
                ENTER PROCESS::<$REPO> := self; # Precomp files should only depend on downstream repos
                LEAVE PROCESS::<$REPO> := $head;

                my $*RESOURCES = Distribution::Resources.new(:repo(self), :$dist-id);
                for $dist.meta<provides>.hash.kv -> $name, $name-path {
                    my $precomp-id  = CompUnit::PrecompilationId.new(self!content-address($dist, $name-path));
                    my $source-file = self.prefix.child($dist-id).child($name-path);

                    state %done;
                    if %done{$precomp-id}++ {
                        note "(Already did $precomp-id)" if %*ENV<RAKUDO_LOG_PRECOMP>;
                        next;
                    }

                    note("Precompiling $precomp-id ($name)") if %*ENV<RAKUDO_LOG_PRECOMP>;
                    $precomp-repo.precompile($source-file, $precomp-id, :source-name("$source-file ($name)"));
                }
            }
        }

        return True;
    }

    method !precomp-stores() {
        $!precomp-stores //= Array[CompUnit::PrecompilationStore].new(
            self.repo-chain.map(*.precomp-store).grep(*.defined)
        )
    }

    method precomp-store(--> CompUnit::PrecompilationStore) {
        $!precomp-store //= CompUnit::PrecompilationStore::File.new(
            :prefix(self.prefix.child('.precomp')),
        )
    }

    method precomp-repository(--> CompUnit::PrecompilationRepository) {
        $!precomp := CompUnit::PrecompilationRepository::Default.new(
            :store(self.precomp-store),
        ) unless $!precomp;
        $!precomp
    }
}

