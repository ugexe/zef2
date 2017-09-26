unit module Zef::Utils::Distribution;

# Provides distribution related routines, typically related to identity
# and meta data generation. This is separate from any Distribution
# class/role because we sometimes want to avoid creating an entire
# Distribution object just to check identity related items (and because
# the rest of the stuff is common to most Distribution implementations).

my grammar DepSpec::Grammar {
    regex TOP { ^^ <name> [':' <key> <value>]* $$ }

    regex name  { <.ident> ['::' <.ident>]* }
    token key   { <-restricted>+ }
    token value { '<' ~ '>'  [<( [[ <!before \>|\\> . ]+]* % ['\\' . ] )>] }

    token ident { <.alpha> [<.alnum> [<.apostrophe> <.alnum>]?]* }
    token apostrophe { ["'" | '-'] }
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

# Given a depspec string or hash, return the normalized depspec string
our proto sub depspec-str(| --> Str) is export {*}
multi sub depspec-str(Str $identity) { samewith($_) with depspec-hash($identity) }
multi sub depspec-str(%_) is export {
    # ignore any nested structures (e.g. dependency hints)
    my %spec = normalize-depspec-hash(%_.grep({ .values.all ~~ Str|Numeric }).hash);

    # create string based on sorted keys, but always put 'name' first
    my $sorted-first-level := %spec.keys.sort.sort: { $^a ne 'name' }
    my $str-parts := $sorted-first-level.map({ $_ eq 'name' ?? %spec{$_} !! ":{$_}<{%spec<< $_ >>}>" });

    return $str-parts.join;
}

# Given a depspec string or hash, return the normalized depspec hash
our proto sub depspec-hash(| --> Str) is export {*}
multi sub depspec-hash(%_) { samewith($_) with depspec-str(%_) }
multi sub depspec-hash(Str $identity --> Hash) is export {
    my $parsed = DepSpec::Grammar.parse($identity, :actions(DepSpec::Actions.new));
    fail "Failed to parse dependency spec - $identity" unless $parsed;
    return normalize-depspec-hash($parsed.ast);
}

# translate the meta "resources" field's values into the "files" field's values
our sub resources-to-files(*@_) is export {
    @_.grep(*.defined).map({
        "resources/$_" => $_ ~~ m/^libraries\/(.*)/
            ?? "resources/libraries/{$*VM.platform-library-name($0.IO)}"
            !! "resources/$_"
    }).hash
}
