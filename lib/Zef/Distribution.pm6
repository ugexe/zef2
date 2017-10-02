use Zef::Utils::FileSystem;
use Zef::Utils::Distribution;


# Methods that can be used on any type of Distribution implementation (mostly search/query related)
role Zef::Distribution {
    has $!identity-cache;

    method meta { ... }

    method identity { $!identity-cache //= depspec-str(%(:name($.meta<name>), :ver($.meta<ver>), :auth($.meta<auth>), :api($.meta<api>))) }

    # [Str, Str, [Str, Str], Str] -> [Spec, Spec, [Spec, Spec], Spec]
    method depends-depspecs       { depends-depspecs($.meta<depends>.list)       }
    method build-depends-depspecs { depends-depspecs($.meta<build-depends>.list) }
    method test-depends-depspecs  { depends-depspecs($.meta<test-depends>.list)  }
    method provides-depspecs { provides-depspecs($.meta.hash) }

    # Check if a depspec derived from any module name in `provides` matches the given $spec
    method provides-matches-depspec($query-spec, Bool :$strict = True) {
        defined provides-matches-depspec($query-spec, $.meta.hash, :$strict)
    }

    # Same as provides-contains-depspec, but also checks the distribution's depspec name
    method matches-depspec($query-spec, Bool :$strict = True) {
        so matches-depspec($query-spec, $.meta.hash, :$strict)
    }
}

# Ideally we just use a `Distribution::Path does Zef::Distribution` without overriding
# method meta, but we do it for now to clean/normalize the meta data.
class Zef::Distribution::FileSystem does Distribution::Locally does Zef::Distribution {
    has %!meta-cache;

    my sub from-json($str) { Rakudo::Internals::JSON.from-json($str) }

    method meta {
        %!meta-cache ||= do {
            my $meta-path = $.prefix.child('META6.json');
            die "No META6 data found at {$.prefix}." unless $meta-path.e;
            my $orig-meta-data = try from-json($meta-path.slurp);
            die "META6 data invalid at {$meta-path.absolute}" unless $orig-meta-data;

            my %meta-data = $orig-meta-data.hash andthen {
                with depspec-hash($_) { .{$^a.keys} = $^a.values }                                   # normalize meta data
                resources-to-files(|$_.<resources>).map: { .<files>{$^a.key} = $^a.value }           # populate `files` field with resources/
                list-paths($.prefix.child('bin')).map: { .<files>{$^a} = $^a.IO.relative($.prefix) } # populate `files` field with bin/
            }
            %meta-data;
        }
    }
}

# Like Distribution::Hash, but uses an extension field `distribution-hash-base64` to map
# each name to a value consisting of the raw base64 encoded file data. This allows one to
# write distributions (like for tests) without needing to create any external files, or that
# are installable from a gist.
class Zef::Distribution::Hash does Distribution does Zef::Distribution {
    has %!meta;
    has %!meta-cache;

    submethod BUILD(:%!meta) {}

    my sub decode-base64(Str:D $str --> Seq) {
        my @alphabet =  flat 'A'..'Z','a'..'z','0'..'9', '+', '/';
        my %lookup   = @alphabet.kv.hash.antipairs;
        $str.comb(/@alphabet/).rotor(4, :partial).map: -> $chunk {
            my $n = [+] $chunk.map: { (%lookup{$_} || 0) +< ((state $m = 24) -= 6) }
            ((16, 8, 0).map({ $n +> $_ +& 255 }).head( 3 - ( 4 - $chunk.elems ) )).Slip
        }
    }

    method meta {
        %!meta-cache ||= do {
            my %meta-data = %!meta andthen {
                with depspec-hash($_) { .{$^a.keys} = $^a.values }
                resources-to-files(|$_.<resources>).map: { .<files>{$^a.key} = $^a.value }
                my %inline-files = .<base64-inline-files>:delete;
                %inline-files.keys.grep(*.starts-with('bin/')).map: { .<files>{$^a} = $^a }
            }
            %meta-data;
        }
    }

    method content($name-path is copy) {
        my $inline-name-path = $name-path.starts-with('resources/libraries/')
            ?? self.meta<files>.hash.first({ .value eq $name-path }).key
            !! $name-path;
        my $base64-content = %!meta<base64-inline-files>{$inline-name-path};

        class :: {
            has $.opened;
            has $!name-path;
            has $!base64-content;
            submethod BUILD(:$!base64-content, :$!name-path, :$!opened = False) { }
            method open(|)  { $!opened = True; self }
            method close(|) { $!opened = False; True }
            method slurp(|c) { Buf.new(decode-base64($!base64-content)) }
            method slurp-rest(|c) { $.slurp(|c) }
            method e { True }
            method f { True }
            method d { False }
            method r { True  }
            method w { False }
        }.new(:name-path($inline-name-path), :$base64-content)
    }
}
