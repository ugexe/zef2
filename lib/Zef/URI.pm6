my grammar RFC3986 {
    token URI-reference { <URI> || <relative-ref>                                   }
    token URI           { <scheme> ':' <heir-part> ['?' <query>]? ['#' <fragment>]? }
    token relative-ref  { <relative-part> ['?' <query>]? ['#' <fragment>]?          }
    token heir-part     {
        || '//' <authority> <path-abempty>
        || <path-absolute>
        || <path-noscheme>
        || <path-empty>
    }
    token relative-part {
        || '//' <authority> <path-abempty>
        || <path-absolute>
        || <path-noscheme>
        || <path-empty>
    }

    token scheme {
        <.alpha>
        [
        || <.alpha>
        || <.digit>
        || '+'
        || '-'
        || '.'
        ]*
    }

    token authority   { [<userinfo> '@']? <host> [':' <port>]? }
    token userinfo    { [<.unreserved> || <.pct-encoded> || <.sub-delims> || ':']*  }
    token host        { <.IP-literal> || <.IPv4address> || <.reg-name>              }
    token IP-literal  { '[' [<.IPv6address> || <.IPv6addrz> || <.IPvFuture>] ']'    }
    token IPv6addz    { <.IPv6address> '%25' <.ZoneID>    }
    token ZoneID      { [<.unreserved> || <.pct-encoded>]+ }
    token IPvFuture   { 'v' <.xdigit>+ '.' [<.unreserved> || <.sub-delims> || ':']+ }
    token IPv6address {
        ||                                      [<.h16>   ':'] ** 6 <.ls32>
        ||                                 '::' [<.h16>   ':'] ** 5 <.ls32>
        || [ <.h16>                     ]? '::' [<.h16>   ':'] ** 4 <.ls32>
        || [[<.h16> ':'] ** 0..1 <.h16> ]? '::' [<.h16>   ':'] ** 3 <.ls32>
        || [[<.h16> ':'] ** 0..2 <.h16> ]? '::' [<.h16>   ':'] ** 2 <.ls32>
        || [[<.h16> ':'] ** 0..3 <.h16> ]? '::'  <.h16>   ':'       <.ls32>
        || [[<.h16> ':'] ** 0..4 <.h16> ]? '::'                     <.ls32>
        || [[<.h16> ':'] ** 0..5 <.h16> ]? '::'  <.h16>
        || [[<.h16> ':'] ** 0..6 <.h16> ]? '::'
    }
    token h16  { <.xdigit> ** 1..4 }
    token ls32 { [<.h16> ':' <.h16>] || <.IPv4address> }
    token IPv4address { <.dec-octet> '.' <.dec-octet> '.' <.dec-octet> '.' <.decoctet> }
    token dec-octet {
        || <.digit>
        || [\x[31]..\x[39]] <.digit>
        || '1' <.digit> ** 2
        || '2'  [\x[30]..\x[34]] <.digit>
        || '25' [\x[30]..\x[35]]
    }
    token reg-name { [<.unreserved> || <.pct-encoded> || <.sub-delims>]* }
    token port     { <.digit>* }

    token path     {
        || <.path-abempty>
        || <.path-absolute>
        || <.path-noscheme>
        || <.path-rootless>
        || <.path-empty>
    }
    token path-abempty  { ['/' <.segment>]*                      }
    token path-absolute { '/' [<.segment-nz> ['/' <.segment>]*]? }
    token path-noscheme { <.segment-nz-nc> ['/' <.segment>]*     }
    token path-rootless { <.segment-nz> ['/' <.segment>]*        }
    token path-empty    { <.pchar> ** 0                          }
    token segment       { <.pchar>* }
    token segment-nz    { <.pchar>+ }
    token segment-nz-nc { [<.unreserved> || <.pct-encoded> || <.sub-delims>]+    }
    token pchar { <.unreserved> || <.pct-encoded> || <.sub-delims> || ':' || '@' || ' ' } # XXX: space is not spec
    token query       { [<.pchar> || '/' || '?']*           }
    token fragment    { [<.pchar> || '/' || '?']*           }
    token pct-encoded { '%' <.xdigit> <.xdigit>             }
    token unreserved  { <.alpha> || <.digit> || < - . _ ~ > }
    token reserved    { <.gen-delims> || <.sub-delims>      }

    token gen-delims  { < : / ? # [ ] @ >         }
    token sub-delims  { < ! $ & ' ( ) * + , ; = > } # ' <- fixes syntax highlighting

}

my grammar RFC8089 is RFC3986 {
    token file-URI { <file-scheme> ':' <file-heir-part> }
    token file-scheme { 'file' }
    token file-heir-part {
        || '//' <auth-path>
        || <local-path>
    }

    token auth-path      {
        || <unc-authority> <path-absolute>
        || <file-auth>? <path-absolute>
        || <file-auth>? <file-absolute>
    }

    token local-path {
        || <drive-letter>? <path-absolute>
        || <file-absolute>
    }

    token file-auth { 
        || 'localhost'
        || [<userinfo> '@']? <host>
    }
    token unc-authority { '//' '/'? <file-host> }

    token file-host {
        || <inline-IP>
        || <IPv4address>
        || <reg-name>
    }

    token inline-IP { '%5B' [<IPv6address> || <IPvFuture>] '%5D' }

    token file-absolute { '/' <drive-letter> <path-absolute> }

    token drive-letter {
        || <alpha> ':'
        || <alpha> '|'
    }
}

grammar Zef::IO::URI {
    method parse($uri, |c) {
        nextwith($uri.subst('\\','/',:g), |c);
    }
    token TOP {
        || <RFC8089::file-URI>
        || <RFC3986::URI>
        || <RFC3986::URI-reference>
    }
}
