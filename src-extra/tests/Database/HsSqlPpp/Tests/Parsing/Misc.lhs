
The automated tests, uses hunit to check a bunch of text expressions
and sql statements parse to the correct tree, and then checks pretty
printing and then reparsing gives the same tree. The code was mostly
written almost in tdd style, which the order/ coverage of these tests
reflects.

There are no tests for invalid syntax at the moment.

> module Database.HsSqlPpp.Tests.Parsing.Misc (miscParserTestData) where
>
> --import Test.HUnit
> --import Test.Framework
> --import Test.Framework.Providers.HUnit
> --import Data.Generics
>
> --import Database.HsSqlPpp.Utils.Here
>
> import Database.HsSqlPpp.Ast
> --import Database.HsSqlPpp.Annotation
> --import Database.HsSqlPpp.Parser
> --import Database.HsSqlPpp.Pretty

> import Database.HsSqlPpp.Tests.Parsing.Utils
>
> miscParserTestData :: Item
> miscParserTestData =
>   Group "miscParserTests" [

>     Group "multiple statements" [
>       s "select 1;\nselect 2;" [QueryStatement ea $ selectE $ sl [SelExp ea (NumberLit ea "1")]
>                                ,QueryStatement ea $ selectE $ sl [SelExp ea (NumberLit ea "2")]]
>      ]
>    ,Group "comments" [
>       s "" []
>      ,s "-- this is a test" []
>      ,s "/* this is\n\
>         \a test*/" []
>      ,s "select 1;\n\
>         \-- this is a test\n\
>         \select -- this is a test\n\
>         \2;" [QueryStatement ea $ selectE $ sl [SelExp ea (NumberLit ea "1")]
>              ,QueryStatement ea $ selectE $ sl [SelExp ea (NumberLit ea "2")]
>              ]
>      ,s "select 1;\n\
>         \/* this is\n\
>         \a test*/\n\
>         \select /* this is a test*/2;"
>                     [QueryStatement ea $ selectE $ sl [SelExp ea (NumberLit ea "1")]
>                     ,QueryStatement ea $ selectE $ sl [SelExp ea (NumberLit ea "2")]
>                     ]
>      ]

--------------------------------------------------------------------------------

ddl statements


>    ,Group "misc" [
>       s "SET search_path TO my_schema, public;"
>         [Set ea "search_path" [SetId ea "my_schema"
>                               ,SetId ea "public"]]
>      ,s "SET t1 = 3;"
>         [Set ea "t1" [SetNum ea 3]]
>      ,s "SET t1 = 'stuff';"
>         [Set ea "t1" [SetStr ea "stuff"]]
>      ,s "create language plpgsql;"
>         [CreateLanguage ea "plpgsql"]
>
>     ]
>     ]
>  where
>    --e = Expr
>    s = Stmt
>    --f = PgSqlStmt