unit module Zef::Utils::Distribution;

# Provides distribution related routines, typically related to identity
# and meta data generation. This is separate from any Distribution
# class/role because we sometimes want to avoid creating an entire
# Distribution object just to check identity related items (and because
# the rest of the stuff is common to most Distribution implementations).

# TODO:
# *) benchmark before/after adding some caching for string parsing (Str -> Hash)
# *) create a depspec type
#   - could retain all levels of meta info (provides, etc)
#   - skip renormalization / reparsing

my grammar DepSpec::Grammar {
    regex TOP { ^^ <name> [':' <key> <value>]* $$ }

    regex name  { <.ident> ['::' <.ident>]* }
    regex key   { <-restricted>+ }
    regex value { '<' ~ '>' [<( [[ <!before \>|\<|\\> . ]+?]* %% ['\\' . ]+ )>] }
    regex ident { <.alpha> [<.alnum> [<.apostrophe> <.alnum>]?]* }

    token apostrophe { ["'" | '-'] }
    token restricted { [':' | '<' | '>' | '(' | ')'] }
}

my class DepSpec::Actions {
    method TOP($/) { make %('name'=> $/<name>.made, %($/<key>>>.ast Z=> $/<value>>>.ast)) if $/ }

    method name($/)  { make $/.Str }
    method key($/)   { make $/.Str }
    method value($/) { make $/.Str }
}

# Set defaults and clean keys/values
my sub normalize-depspec-hash(
    %spec
    [
        :$name!,
        :$auth          = '',
        :$api           = '*',
        :version(:$ver) = '*',
        *%_
    ]
--> Hash) {
    %(
        :$name,
        :$auth,
        :api($api.Str.substr(+$api.Str.starts-with('v'))),
        :ver($ver.Str.substr(+$ver.Str.starts-with('v'))),
        |%_
    )
}

# Sort depspecs based on their version and api
our proto sub depspec-sort(|) is export {*}
multi sub depspec-sort(@values) { nextwith(@values) }
multi sub depspec-sort(+values) is export {
    values\
        .map({ Pair.new(depspec-hash($_.hash), $_) })\
        .sort({ Version.new($_[0].key<api>) })\ # The key gets wrapped with `( )`
        .sort({ Version.new($_[0].key<ver>) })\ # for some reason, hence the [0].
        .map({ .value }); # .key is a first-level-only copy we used to sort with, and .value is the original
}

# See if a depspec ($haystack) fulfills a request for a despec query ($needle)
# - $needle should contain concrete matchers (:ver('1.5') - e.g. no * or +)
# - $haystack could contain concrete or ranges (:ver('1.5+'), :ver('1.*'), :ver('1.5'))
our sub depspec-match($needle, $haystack, Bool:D :$strict = True --> Bool) is export {
    my %query-spec = depspec-hash($needle);
    my %spec       = depspec-hash($haystack);

    # don't even try to match if there is no name
    return False unless %query-spec<name>.chars && %spec<name>.chars;

    # match name - if $strict is False it will match the name as a pattern
    return False unless $strict
        ?? (%query-spec<name>.lc eq %spec<name>.lc)
        !! (%spec<name>.match($_) with %query-spec<name>);

    # match auth - only accepts an exact string match
    return False if %query-spec<auth>.chars && %query-spec<auth> ne %spec<auth>;

    return False if %query-spec<ver>.chars
        && %query-spec<ver> ne '*'
        && %spec<ver>       ne '*'
        && Version.new(%spec<ver>) !~~ Version.new(%query-spec<ver>);

    # match api - same as `match version`
    return False if %query-spec<api>.chars
        && %query-spec<api> ne '*'
        && %spec<api>       ne '*'
        && Version.new(%spec<api>) !~~ Version.new(%query-spec<api>);

    # if we made it here then we must be a match
    return True;
}

# Expects a depspec string or hash, and return the normalized depspec string
our proto sub depspec-str(| --> Str) is export {*}
multi sub depspec-str(Str:D $identity) { samewith($_) with depspec-hash($identity) }
multi sub depspec-str(%_) is export {
    my &escape-spec-value = { $^a.subst(:g, /<!after \\> \</, '\<').subst(:g, /<!after \\> \>/, '\>') }

    # ignore any nested structures (e.g. dependency hints)
    # TODO: redo this!
    my %first-level = normalize-depspec-hash(
        %_.keys.grep({ %_{$_} }).grep({ %_{$_} ~~ Str|Int|Num|Bool|Version }).map({ $_ => %_{$_} }).hash
    ).hash;

    # create string based on sorted keys, but always put 'name' first
    my $sorted-first-level := %first-level.keys.sort.sort: { $^a ne 'name' }

    my $str-parts := $sorted-first-level.map({ $_ eq 'name' ?? %first-level{$_} !! ":{$_}<{escape-spec-value(%first-level<< $_ >>.Str)}>" }).cache;
    return $str-parts.join;
}

# Expects a depspec string or hash, and returns the normalized depspec hash
our proto sub depspec-hash(| --> Str) is export {*}
multi sub depspec-hash(%_) { samewith($_) with depspec-str(%_) }
multi sub depspec-hash(Str:D $identity --> Hash) is export {
    my $parsed = DepSpec::Grammar.parse($identity, :actions(DepSpec::Actions.new));
    fail "Failed to parse dependency spec - $identity" unless $parsed;
    return normalize-depspec-hash($parsed.ast);
}

# Expects a list of depends, test-depends, etc and returns with all leaf nodes as depspecs
our sub depends-depspecs(@_) is export {
    @_.map({ $_ ~~ List|Array ?? $_>>.&?BLOCK.list !! depspec-hash(environment-query($_)) }).grep(*.defined);
}

# Expects a META6 spec hash and return the provides section with the keys (module names) as depspecs
our sub provides-depspecs(%meta) is export {
    %meta<provides>.keys.map({ depspec-hash($_) }).map: {
        .<api>  = %meta<api>  if %meta<api>.defined  && .<api>  eq '*'; # e.g. use the distribution's
        .<auth> = %meta<auth> if %meta<auth>.defined && .<auth> eq '';  # value for these fields if not
        .<ver>  = %meta<ver>  if %meta<ver>.defined  && .<ver>  eq '*'; # included in any provide spec strings.
        $_
    }
}

# Check if a depspec derived from any module name in `provides` matches the given $spec
our sub provides-matches-depspec($query-spec, %meta, Bool :$strict = True) is export {
    provides-depspecs(%meta).first: { depspec-match($query-spec, $_, :$strict) }
}

# Same as provides-matches-depspec, but also checks the distribution's depspec name
our sub matches-depspec($query-spec, %meta, Bool :$strict = True) is export {
    so depspec-match($query-spec, %meta, :$strict) || provides-matches-depspec($query-spec, %meta, :$strict)
}

# Translate the meta "resources" field's values into the "files" field's values
our sub resources-to-files(*@_) is export {
    @_.grep(*.defined).map({
        "resources/$_" => $_ ~~ m/^libraries\/(.*)/
            ?? "resources/libraries/{$*VM.platform-library-name($0.IO)}"
            !! "resources/$_"
    }).hash
}

# Resolve declarative dependencies
our sub environment-query($data) is export {
    return $data unless $data ~~ Hash|Array;

    my sub walk(@path, $idx, $query-source) {
        die "Attempting to find \$*{@path[0].uc}.{@path[1..*].join('.')}"
            if !$query-source.^can("{@path[$idx]}") && $idx < @path.elems;
        return $query-source."{@path[$idx]}"()
            if $idx+1 == @path.elems;
        return walk(@path, $idx+1, $query-source."{@path[$idx]}"());
    }

    my $return = $data.WHAT.new;

    for $data.keys -> $idx {
        given $idx {
            when /^'by-env-exists'/ {
                my $key = $idx.split('.')[1];
                my $value = %*ENV{$key}:exists ?? 'yes' !! 'no';
                die "Unable to resolve path: {$idx} in \%*ENV\nhad: {$value}"
                    unless $data{$idx}{$value}:exists;
                return environment-query($data{$idx}{$value});
            }
            when /^'by-env'/ {
                my $key = $idx.split('.')[1];
                my $value = %*ENV{$key};
                die "Unable to resolve path: {$idx} in \%*ENV\nhad: {$value // ''}"
                    unless defined($value) && ($data{$idx}{$value}:exists);
                return environment-query($data{$idx}{$value});
            }
            when /^'by-' (distro|kernel|perl|vm)/ {
                my $query-source = do given $/[0] {
                    when 'distro' { $*DISTRO }
                    when 'kernel' { $*KERNEL }
                    when 'perl'   { $*PERL   }
                    when 'vm'     { $*VM     }
                }
                my $path  = $idx.split('.');
                my $value = walk($path, 1, $query-source);
                my $fkey  = ($data{$idx}{$value}:exists)
                    ?? $value
                    !! ($data{$idx}{''}:exists)
                        ?? ''
                        !! Any;

                die "Unable to resolve path: {$path.cache[*-1].join('.')} in \$*DISTRO\nhad: {$value} ~~ {$value.WHAT.^name}"
                    if Any ~~ $fkey;
                return environment-query($data{$idx}{$fkey});
            }
            default {
                my $val = environment-query($data ~~ Array ?? $data[$idx] !! $data{$idx});
                $return{$idx} = $val
                    if $return ~~ Hash;
                $return.push($val)
                    if $return ~~ Array;

            }
        };
    }

    return $return;
}
