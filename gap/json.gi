#
# ArtifactManager: Download, verify, and manage external data artifacts for GAP packages
#
# json.gi: a small recursive descent JSON parser.  See json.gd.
#
# Failure sets 'st.err' rather than raising: GAP's 'Error' enters the break
# loop even inside 'CALL_WITH_CATCH'.  Check 'st.err' after any call that can
# fail.
#

BindGlobal( "AM_JsonWhitespace", " \t\r\n" );

# Append the UTF-8 encoding of the code point <cp> to <res>.
BindGlobal( "AM_JsonAppendUTF8",
function( res, cp )
  if cp < 128 then
    Add( res, CharInt( cp ) );
  elif cp < 2048 then
    Add( res, CharInt( 192 + QuoInt( cp, 64 ) ) );
    Add( res, CharInt( 128 + RemInt( cp, 64 ) ) );
  elif cp < 65536 then
    Add( res, CharInt( 224 + QuoInt( cp, 4096 ) ) );
    Add( res, CharInt( 128 + RemInt( QuoInt( cp, 64 ), 64 ) ) );
    Add( res, CharInt( 128 + RemInt( cp, 64 ) ) );
  else
    Add( res, CharInt( 240 + QuoInt( cp, 262144 ) ) );
    Add( res, CharInt( 128 + RemInt( QuoInt( cp, 4096 ), 64 ) ) );
    Add( res, CharInt( 128 + RemInt( QuoInt( cp, 64 ), 64 ) ) );
    Add( res, CharInt( 128 + RemInt( cp, 64 ) ) );
  fi;
end );

BindGlobal( "AM_JsonParse",
function( str )
  local st, complain, skip, expect, literal, hex4, parseString, parseNumber,
        parseValue, res;

  st := rec( pos := 1, err := fail );

  complain := function( msg )
    if st.err = fail then
      st.err := Concatenation( "invalid JSON: ", msg, " at position ",
                               String( st.pos ) );
    fi;
  end;

  skip := function()
    while st.pos <= Length( str ) and str[ st.pos ] in AM_JsonWhitespace do
      st.pos := st.pos + 1;
    od;
  end;

  expect := function( char )
    skip();
    if st.pos > Length( str ) or str[ st.pos ] <> char then
      complain( Concatenation( "expected '", [ char ], "'" ) );
      return false;
    fi;
    st.pos := st.pos + 1;
    return true;
  end;

  literal := function( word )
    if st.pos + Length( word ) - 1 > Length( str ) or
       str{ [ st.pos .. st.pos + Length( word ) - 1 ] } <> word then
      return false;
    fi;
    st.pos := st.pos + Length( word );
    return true;
  end;

  hex4 := function()
    local val, i, d;
    if st.pos + 3 > Length( str ) then
      complain( "truncated \\u escape" );
      return 0;
    fi;
    val := 0;
    for i in [ 0 .. 3 ] do
      d := Position( AM_HexDigits,
               LowercaseString( [ str[ st.pos + i ] ] )[1] );
      if d = fail then
        complain( "bad \\u escape" );
        return 0;
      fi;
      val := val * 16 + ( d - 1 );
    od;
    st.pos := st.pos + 4;
    return val;
  end;

  parseString := function()
    local res, c, cp, low;

    if not expect( '"' ) then
      return "";
    fi;
    res := "";
    while true do
      if st.pos > Length( str ) then
        complain( "unterminated string" );
        return res;
      fi;
      c := str[ st.pos ];
      st.pos := st.pos + 1;
      if c = '"' then
        return res;
      elif c <> '\\' then
        Add( res, c );
      else
        if st.pos > Length( str ) then
          complain( "unterminated escape" );
          return res;
        fi;
        c := str[ st.pos ];
        st.pos := st.pos + 1;
        if   c = '"'  then Add( res, '"' );
        elif c = '\\' then Add( res, '\\' );
        elif c = '/'  then Add( res, '/' );
        elif c = 'b'  then Add( res, CharInt( 8 ) );
        elif c = 'f'  then Add( res, CharInt( 12 ) );
        elif c = 'n'  then Add( res, '\n' );
        elif c = 'r'  then Add( res, '\r' );
        elif c = 't'  then Add( res, '\t' );
        elif c = 'u'  then
          cp := hex4();
          if st.err <> fail then
            return res;
          fi;
          # A high surrogate must be followed by a low one.
          if cp >= 55296 and cp < 56320 then
            if st.pos + 1 <= Length( str ) and str[ st.pos ] = '\\'
               and str[ st.pos + 1 ] = 'u' then
              st.pos := st.pos + 2;
              low := hex4();
              if st.err <> fail then
                return res;
              fi;
              if low >= 56320 and low < 57344 then
                cp := 65536 + ( cp - 55296 ) * 1024 + ( low - 56320 );
              else
                complain( "bad surrogate pair" );
                return res;
              fi;
            else
              complain( "lone high surrogate" );
              return res;
            fi;
          fi;
          AM_JsonAppendUTF8( res, cp );
        else
          complain( "unknown escape" );
          return res;
        fi;
      fi;
    od;
  end;

  parseNumber := function()
    local start, text;

    start := st.pos;
    while st.pos <= Length( str ) and
          str[ st.pos ] in "0123456789+-.eE" do
      st.pos := st.pos + 1;
    od;
    text := str{ [ start .. st.pos - 1 ] };
    if text = "" then
      complain( "expected a value" );
      return fail;
    fi;

    if ForAll( text, c -> c in "0123456789" ) or
       ( text[1] = '-' and Length( text ) > 1 and
         ForAll( text{ [ 2 .. Length( text ) ] },
                 c -> c in "0123456789" ) ) then
      return Int( text );
    fi;
    return Float( text );
  end;

  # Recursive: the inner uses resolve to this local variable.
  parseValue := function()
    local res, key, c;

    skip();
    if st.pos > Length( str ) then
      complain( "unexpected end of input" );
      return fail;
    fi;
    c := str[ st.pos ];

    if c = '{' then
      st.pos := st.pos + 1;
      res := rec();
      skip();
      if st.pos <= Length( str ) and str[ st.pos ] = '}' then
        st.pos := st.pos + 1;
        return res;
      fi;
      while true do
        skip();
        key := parseString();
        if st.err <> fail then return res; fi;
        if not expect( ':' ) then return res; fi;
        res.( key ) := parseValue();
        if st.err <> fail then return res; fi;
        skip();
        if st.pos > Length( str ) then
          complain( "unterminated object" );
          return res;
        elif str[ st.pos ] = ',' then
          st.pos := st.pos + 1;
        elif str[ st.pos ] = '}' then
          st.pos := st.pos + 1;
          return res;
        else
          complain( "expected ',' or '}'" );
          return res;
        fi;
      od;

    elif c = '[' then
      st.pos := st.pos + 1;
      res := [];
      skip();
      if st.pos <= Length( str ) and str[ st.pos ] = ']' then
        st.pos := st.pos + 1;
        return res;
      fi;
      while true do
        Add( res, parseValue() );
        if st.err <> fail then return res; fi;
        skip();
        if st.pos > Length( str ) then
          complain( "unterminated array" );
          return res;
        elif str[ st.pos ] = ',' then
          st.pos := st.pos + 1;
        elif str[ st.pos ] = ']' then
          st.pos := st.pos + 1;
          return res;
        else
          complain( "expected ',' or ']'" );
          return res;
        fi;
      od;

    elif c = '"' then
      return parseString();
    elif literal( "true" ) then
      return true;
    elif literal( "false" ) then
      return false;
    elif literal( "null" ) then
      return fail;
    else
      return parseNumber();
    fi;
  end;

  res := parseValue();
  if st.err = fail then
    skip();
    if st.pos <= Length( str ) then
      complain( "unexpected trailing data" );
    fi;
  fi;

  if st.err <> fail then
    return rec( success := false, error := st.err );
  fi;
  return rec( success := true, value := res );
end );


#############################################################################
##
#F  AM_JsonToGap( <str> )
##
InstallGlobalFunction( AM_JsonToGap,
function( str )
  if not IsString( str ) then
    ErrorNoReturn( "<str> must be a string" );
  fi;

  # Not delegated to the 'json' package even when loaded: two parsers means
  # two sets of edge cases, and a manifest that parses on one machine but not
  # another is a horrible bug to chase.
  return AM_JsonParse( str );
end );

InstallGlobalFunction( AM_JsonFileToGap,
function( path )
  local data;

  if not IsExistingFile( path ) then
    return rec( success := false,
                error := Concatenation( "no such file: ", path ) );
  fi;
  data := StringFile( path );
  if data = fail then
    return rec( success := false,
                error := Concatenation( "cannot read ", path ) );
  fi;
  return AM_JsonToGap( data );
end );
