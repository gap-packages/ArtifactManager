# ArtifactManager: the JSON parser
#
#@local r
gap> START_TEST("json.tst");

# Basic values
gap> AM_JsonToGap("{}").value;
rec(  )
gap> AM_JsonToGap("[]").value;
[  ]
gap> AM_JsonToGap("  [ 1 , 2 ,3 ]  ").value;
[ 1, 2, 3 ]
gap> AM_JsonToGap("{\"a\": 1, \"b\": [true, false]}").value;
rec( a := 1, b := [ true, false ] )
gap> AM_JsonToGap("-17").value;
-17
gap> AM_JsonToGap("2.5").value = Float("2.5");
true

# JSON null becomes fail.  We never write null ourselves, and treat it as
# "absent" when reading, so the ambiguity with a genuine fail cannot bite.
gap> AM_JsonToGap("null").value;
fail

# Strings and escapes
gap> AM_JsonToGap("\"a\\nb\"").value = "a\nb";
true
gap> AM_JsonToGap("\"\\u0041\\u00e4\"").value = "A\303\244";
true
gap> AM_JsonToGap("\"\\ud83d\\ude00\"").value = "\360\237\230\200";
true

# Nesting
gap> AM_JsonToGap("{\"a\":{\"b\":{\"c\":[[]]}}}").value.a.b.c;
[ [  ] ]

# Failures must come back as a value, never as an error: a manifest is
# untrusted input, and a package author's typo must not drop the user into a
# break loop.
gap> r := AM_JsonToGap("{bad}");;
gap> r.success;
false
gap> IsString(r.error);
true
gap> AM_JsonToGap("{} extra").success;
false
gap> AM_JsonToGap("[1,2").success;
false
gap> AM_JsonToGap("{\"a\": }").success;
false
gap> AM_JsonToGap("\"unterminated").success;
false
gap> AM_JsonToGap("").success;
false
gap> AM_JsonToGap("tru").success;
false
gap> AM_JsonToGap("\"\\q\"").success;
false
gap> AM_JsonToGap("\"\\ud83d\"").success;
false

#
gap> STOP_TEST("json.tst");
