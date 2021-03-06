
> {-# LANGUAGE OverloadedStrings #-}
> module Database.HsSqlPpp.Tests.TypeChecking.ImplicitCasts
>     (impCasts) where

> import Database.HsSqlPpp.Tests.TestTypes
> --import Database.HsSqlPpp.Types
> import Database.HsSqlPpp.Dialect
> --import Database.HsSqlPpp.TypeCheck
> import Data.Text.Lazy ()


> impCasts :: Item
> impCasts =
>   Group "impCasts"
>   [e p "'1' + 2" "'1' :: int4 + 2"
>   ,e p "1.5 :: numeric between 1.1 and 2"
>        "1.5 :: numeric between 1.1 and 2 :: numeric"
>   ,e p "'aa'::text = 'bb'"
>        "'aa'::text = 'bb'::text"
>   ,e s "cast(1 as int4) + cast('2' as varchar)"
>        "cast(1 as int4) + cast(cast('2' as varchar) as int4)"
>   ]
>   where
>     e = ImpCastsScalar
>     p = defaultTypeCheckFlags {tcfDialect=postgresDialect}
>     s = defaultTypeCheckFlags {tcfDialect=sqlServerDialect}
