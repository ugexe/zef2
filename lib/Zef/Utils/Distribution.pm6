unit module Zef::Utils::Distribution;

my grammar DepSpec::Grammar {
    regex TOP { ^^ <name> [':' <key> <value>]* $$ }

    regex name  { <-restricted>+ ['::' <-restricted>+]* }
    token key   { <-restricted>+ }
    token value { '<' ~ '>'  [<( [[ <!before \>|\\> . ]+]* % ['\\' . ] )>] }

    token restricted { [':' | '<' | '>' | '(' | ')'] }
}

# todo: handle (ignore?) top level keys that has a non-string value
my class DepSpec::Actions {
    method TOP($/) { make %('name'=> $/<name>.made, %($/<key>>>.ast Z=> $/<value>>>.ast)) if $/ }

    method name($/)  { make $/.Str }
    method key($/)   { make $/.Str }
    method value($/) { make $/.Str }
}

# normalize - set defaults and clean keys/values
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
        :api($api.substr(+$api.starts-with('v'))),
        :ver($ver.substr(+$ver.starts-with('v'))),
        |%_
    )
}

# does spec match against query-spec?
# - spec should contain concrete matchers (:ver('1.5') - e.g. no * or +)
# - query-spec could contain concrete or ranges (:ver('1.5+'), :ver('1.*'), :ver('1.5'))
# (depspec-hash-match separate from `depspec-match` to avoid calling normalize-depspec-hash twice when passing strings)
my sub depspec-hash-match(%spec, %query-spec, Bool :$strict = True --> Bool) {
    # don't even try to match if there is no name
    return False unless %query-spec<name>.chars && %spec<name>.chars;

    # match name - if $strict is False it will match the name as a pattern
    return False unless $strict 
        ?? (%query-spec<name>.lc eq %spec<name>.lc)
        !! (%spec<name>.match(%query-spec<name>) with %query-spec<name>);

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

# depspec matching interface
our proto sub depspec-match(|) is export {*}
multi sub depspec-match(Str $spec, Str $query-spec, |c) {
    depspec-hash-match(from-depspec($spec), from-depspec($query-spec), |c)
}
multi sub depspec-match(%spec, Str $query-spec, |c) {
    depspec-hash-match(%spec, from-depspec($query-spec), |c)
}
multi sub depspec-match(Str $spec, %query-spec, |c) {
    depspec-hash-match(from-depspec($spec), %query-spec, |c)
}
multi sub depspec-match(%spec, %query-spec, |c) {
    depspec-hash-match(normalize-depspec-hash(%spec), normalize-depspec-hash(%query-spec), |c)
}

# hash to depspec string
our sub to-depspec(%_ --> Str) is export {
    my %spec = normalize-depspec-hash(%_);

    # create string based on sorted keys, but always put 'name' first
    my $str  = %spec.keys.sort.sort({$^a ne 'name'}).map({ $_ eq 'name' ?? %spec{$_} !! ":{$_}<{%spec<< $_ >>}>" }).join;
    return $str;
}

# depspec string to hash
our sub from-depspec(Str $identity --> Hash) is export {
    my $parsed = DepSpec::Grammar.parse($identity, :actions(DepSpec::Actions.new))
        or fail "Failed to parse dependency spec - $identity";
    return normalize-depspec-hash($parsed.ast);
}

# translate the meta "resources" field's values into the "files" field's values
our sub resources-to-files(*@_) is export {
    @_.map({
        $_ => $_ ~~ m/^libraries\/(.*)/
            ?? "resources/libraries/{$*VM.platform-library-name($0.IO)}"
            !! "resources/{$_}"
    }).hash
}
