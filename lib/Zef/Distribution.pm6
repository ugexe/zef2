use Zef::Utils::FileSystem;
use Zef::Utils::Distribution;

# For the most part we only work with one type of Distribution, Distribution::Path (Zef::Distribution::FileSystem).
# This is because we generally want to do file operations before installation and thus usually end up with such
# a distribution. However, we -could- have a Zef::Distribution::Tar that does not extract any data to the file
# system, and instead pipes data from the tar command to stdout. This means installation would extract each file
# at the moment rakudo tries to install it.

role Zef::Distribution {
    has $!identity-cache;
    has @!provides-cache;
    has @!depends-cache;
    has @!build-depends-cache;
    has @!test-depends-cache;

    method meta { ... }

    method identity { $!identity-cache //= depspec-str(%(:name($.meta<name>), :ver($.meta<ver>), :auth($.meta<auth>), :api($.meta<api>))) }

    # [Str, Str, [Str, Str], Str] -> [Spec, Spec, [Spec, Spec], Spec] (including "alternative" deps)
    method !specs-listing(*@_) { @_.map({ $_ ~~ Iterable ?? $_>>.&?BLOCK !! depspec-hash($_) }).grep(*.defined) }
    method depends-depspecs       { @!depends-cache       ||= self!specs-listing(|$.meta<depends>)       }
    method build-depends-depspecs { @!build-depends-cache ||= self!specs-listing(|$.meta<build-depends>) }
    method test-depends-depspecs  { @!test-depends-cache  ||= self!specs-listing(|$.meta<test-depends>)  }
    method provides-depspecs      {
        @!provides-cache ||= self!specs-listing(|$.meta<provides>.hash.keys).map: {
            .<api>  = $.meta<api>  if .<api> eq '*'; # e.g. use the distribution's
            .<auth> = $.meta<auth> if .<auth> eq ''; # value for these fields if not
            .<ver>  = $.meta<ver>  if .<ver> eq '*'; # included in any provide spec strings.
            $_
        }
    }

    # Check if a depspec derived from any module name in `provides` matches the given $spec
    method provides-matches-depspec($query-spec, Bool :$strict = True) {
        defined $.provides-depspecs.first: { depspec-match($query-spec, $_, :$strict) }
    }

    # Same as provides-contains-depspec, but also checks the distribution's depspec name
    method matches-depspec($query-spec, Bool :$strict = True) {
        so depspec-match($query-spec, $.identity, :$strict) || self.provides-matches-depspec($query-spec, :$strict)
    }
}

# Ideally we just use a `Distribution::Path does Zef::Distribution` without
# overriding method meta, but we do it for now to clean/normalize the meta data.
class Zef::Distribution::FileSystem is Distribution::Path does Zef::Distribution {
    also does Distribution;
    has %!meta-cache;

    my sub from-json($str) { Rakudo::Internals::JSON.from-json($str) }

    method meta {
        %!meta-cache ||= do {
            my $meta-path = $.prefix.child('META6.json');
            die "No META6 data found at {$.prefix}." unless $meta-path.e;

            my $orig-meta-data = try from-json($meta-path.slurp);
            die "META6 data invalid at {$meta-path.absolute}" unless $orig-meta-data;

            my %meta-data = $orig-meta-data.hash andthen {
                # normalize meta data
                my %cleaned = depspec-hash($_);
                %cleaned.keys.map: -> $root-field { .{$root-field} = %cleaned{$root-field} }

                # populate `files` fields for bin/ and resources/
                resources-to-files(|$_.<resources>).map: -> $resource { .<files>{$resource.key} = $resource.value }
                list-paths($.prefix.child('bin')).map: -> $bin { .<files>{$bin} = $bin.IO.relative($.prefix) }
            }
            %meta-data;
        }
    }
}

