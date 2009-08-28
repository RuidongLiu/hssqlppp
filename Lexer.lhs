Copyright 2009 Jake Wheat

This file contains the lexer for sql text.

Lexicon:

string
identifier or keyword
symbols - operators and ;,()[]
positional arg
int
float
copy payload (used to lex copy from stdin data)

The symbol element is single symbol character:

approach 1:
try to keep multi symbol operators as single lexical items
(e.g. "==", "~=="

approach 2:
make each character a separate element
e.g. == lexes to ['=', '=']
then the parser sorts this out

try approach 2 for now (THIS IS REALLY WRONG, will have to be fixed to
parse full symbols at some point since the parser needs to distinguish
between symbols with whitespace between them and with no whitespace
between them)

== notes on symbols in pg operators
pg symbols can be made from:

=_*/<>=~!@#%^&|`?

no --, /* in symbols

can't end in + or - unless contains
~!@#%^&|?

Most of this isn't relevant for the current lexer.

Don't know if its proper vernaculaic usage, but the docs in this file
refer to the parsers which form the lexing stage as lexers, and the
parsers which use the lexed tokens as parsers, to make it clear which
part of parsing is being referred to. If that makes sense?

> module Lexer (
>               Token
>              ,Tok(..)
>              ,lexSqlFile
>              ,lexSqlText
>              ) where

> import Text.Parsec hiding(many, optional, (<|>))
> import qualified Text.Parsec.Token as P
> import Text.Parsec.Language
> import Text.Parsec.String

> import Control.Applicative
> import Control.Monad.Identity

> import Data.Char

> import ParseErrors

================================================================================

= data types

> type Token = (SourcePos, Tok)

> data Tok = StringTok String String --delim, value (delim will one of
>                                    --', $$, $[stuff]$
>          | IdStringTok String --includes . and x.y.* type stuff
>          | SymbolTok String -- operators, and ()[],;:
>                             -- * is currently always lexed as an id
>                             --   rather than an operator
>                             -- this gets fixed in the parsing stage
>          | PositionalArgTok Integer -- $1, etc.
>          | FloatTok Double
>          | IntegerTok Integer
>          | CopyPayloadTok String -- support copy from stdin; with inline data
>            deriving (Eq,Show)

> type ParseState = [Tok]

> lexSqlFile :: FilePath -> IO (Either ExtendedError [Token])
> lexSqlFile f = do
>   te <- readFile f
>   let x = runParser sqlTokens [] f te --parseFromFile sqlTokens f
>   return $ convertToExtendedError x f te

> lexSqlText :: String -> Either ExtendedError [Token]
> lexSqlText s = convertToExtendedError (runParser sqlTokens [] "" s) "" s

================================================================================

= lexers

lexer for tokens, contains a hack for copy from stdin with inline
table data.

> sqlTokens :: ParsecT String ParseState Identity [Token]
> sqlTokens =
>   setState [] >>
>   whiteSpace >>
>   many sqlToken <* eof

Parser for an individual token.

What we should do is lex lazily and when the lexer reads a copy from
stdin statement, it switches lexers to lex the inline table data, then
switches back. Don't know how to do this in parsec, or even if it is
possible, so as a work around, we use the state to trap if we've just
seen 'from stdin;', if so, we read the copy payload, otherwise we read
a normal token.

> sqlToken :: ParsecT String ParseState Identity Token
> sqlToken = do
>            sp <- getPosition
>            sta <- getState
>            t <- if sta == [ft,st,mt]
>                 then copyPayload
>                 else (try sqlString
>                  <|> try idString
>                  <|> try positionalArg
>                  <|> try sqlSymbol
>                  <|> try sqlFloat
>                  <|> try sqlInteger)
>            updateState $ \stt ->
>              case () of
>                      _ | stt == [] && t == ft -> [ft]
>                        | stt == [ft] && t == st -> [ft,st]
>                        | stt == [ft,st] && t == mt -> [ft,st,mt]
>                        | True -> []

>            return (sp,t)
>            where
>              ft = IdStringTok "from"
>              st = IdStringTok "stdin"
>              mt = SymbolTok ";"

== specialized token parsers

> sqlString :: ParsecT String ParseState Identity Tok
> sqlString = stringQuotes <|> stringLD
>   where
>     --parse a string delimited by single quotes
>     stringQuotes = StringTok "\'" <$> stringPar
>     stringPar = optional (char 'E') *> char '\''
>                 *> readQuoteEscape <* whiteSpace
>     --(readquoteescape reads the trailing ')

have to read two consecutive single quotes as a quote character
instead of the end of the string, probably an easier way to do this

other escapes (e.g. \n \t) are left unprocessed

>     readQuoteEscape = do
>                       x <- anyChar
>                       if x == '\''
>                         then try ((x:) <$> (char '\'' *> readQuoteEscape))
>                              <|> return ""
>                         else (x:) <$> readQuoteEscape

parse a dollar quoted string

>     stringLD = do
>                -- cope with $$ as well as $[identifier]$
>                tag <- try (char '$' *> ((char '$' *> return "")
>                                    <|> (identifierString <* char '$')))
>                s <- lexeme $ manyTill anyChar
>                       (try $ char '$' <* string tag <* char '$')
>                return $ StringTok ("$" ++ tag ++ "$") s

> idString :: ParsecT String ParseState Identity Tok
> idString = IdStringTok <$> identifierString

> positionalArg :: ParsecT String ParseState Identity Tok
> positionalArg = char '$' >> PositionalArgTok <$> integer

sql symbol is one of
()[],; - single character
: or :: symbol
+-*/<>=~!@#%^&|`? string - one or more of these, parsed until hit char
which isn't one of these (including whitespace). This will parse some
standard sql expressions wrongly at the moment, work around is to add
whitespace e.g. i think 3*-4 is valid sql, should lex as '3' '*' '-'
'4', but will currently lex as '3' '*-' '4'. Maybe this will be fixed
in the parser instead?

some other special cases are operators with non standard chars in them
e.g.
.. := ::

> sqlSymbol :: ParsecT String ParseState Identity Tok
> sqlSymbol =
>   SymbolTok <$> lexeme (choice [
>                          replicate 1 <$> oneOf "()[],;"
>                         ,string ".."
>                         ,try $ string "::"
>                         ,try $ string ":="
>                         ,string ":"
>                         ,many1 (oneOf "+-*/<>=~!@#%^&|`?")
>                         ])

> sqlFloat :: ParsecT String ParseState Identity Tok
> sqlFloat = FloatTok <$> float

> sqlInteger :: ParsecT String ParseState Identity Tok
> sqlInteger = IntegerTok <$> integer

================================================================================

additional parser bits and pieces

include dots, * in all identifier strings during lexing. This parser
is also used for keywords, so identifiers and keywords aren't distinguished
until during proper parsing

> identifierString :: ParsecT String ParseState Identity String
> identifierString = lexeme $ choice [
>                     "*" <$ symbol "*"
>                    ,do
>                      a <- nonStarPart
>                      b <- tryMaybeP ((++) <$> symbol "." <*> identifierString)
>                      case b of Nothing -> return a
>                                Just c -> return $ a ++ c]
>   where
>     nonStarPart = letter <:> secondOnwards
>     secondOnwards = many (alphaNum <|> char '_')

parse the block of inline data for a copy from stdin, ends with \. on
its own on a line

> copyPayload :: ParsecT String ParseState Identity Tok
> copyPayload = CopyPayloadTok <$> lexeme (getLinesTillMatches "\\.\n")
>   where
>     getLinesTillMatches s = do
>                             x <- getALine
>                             if x == s
>                               then return ""
>                               else (x++) <$> getLinesTillMatches s
>     getALine = (++"\n") <$> manyTill anyChar (try newline)

doesn't seem too gratuitous, comes up a few times

> (<:>) :: (Applicative f) =>
>          f a -> f [a] -> f [a]
> (<:>) a b = (:) <$> a <*> b

> tryMaybeP :: GenParser tok st a
>           -> ParsecT [tok] st Identity (Maybe a)
> tryMaybeP p = try (optionMaybe p) <|> return Nothing


================================================================================

= parsec pass throughs

> symbol :: String -> ParsecT String ParseState Identity String
> symbol = P.symbol lexer

> integer :: ParsecT String ParseState Identity Integer
> integer = lexeme $ P.integer lexer

> float :: ParsecT String ParseState Identity Double
> float = lexeme $ P.float lexer

> whiteSpace :: ParsecT String ParseState Identity ()
> whiteSpace= P.whiteSpace lexer

> lexeme :: ParsecT String ParseState Identity a
>           -> ParsecT String ParseState Identity a
> lexeme = P.lexeme lexer

this lexer isn't really used as much as it could be, probably some of
the fields are not used at all (like identifier and operator stuff)

> lexer :: P.GenTokenParser String ParseState Identity
> lexer = P.makeTokenParser (emptyDef {
>                             P.commentStart = "/*"
>                            ,P.commentEnd = "*/"
>                            ,P.commentLine = "--"
>                            ,P.nestedComments = False
>                            ,P.identStart = letter <|> char '_'
>                            ,P.identLetter    = alphaNum <|> oneOf "_"
>                            ,P.opStart        = P.opLetter emptyDef
>                            ,P.opLetter       = oneOf opLetters
>                            ,P.reservedOpNames= []
>                            ,P.reservedNames  = []
>                            ,P.caseSensitive  = False
>                            })

> opLetters :: String
> opLetters = ".:^*/%+-<>=|!"
