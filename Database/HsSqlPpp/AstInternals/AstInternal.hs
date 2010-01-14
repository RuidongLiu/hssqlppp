

-- UUAGC 0.9.11 (AstInternal.ag)
module Database.HsSqlPpp.AstInternals.AstInternal(
    -- {-# LANGUAGE DeriveDataTypeable,RankNTypes,ScopedTypeVariables #-}
    -- {-# OPTIONS_HADDOCK hide  #-}
    --from the ag files:
    --ast nodes
    Statement (..)
   ,SelectExpression (..)
   ,FnBody (..)
   ,SetClause (..)
   ,TableRef (..)
   ,TableAlias(..)
   ,JoinExpression (..)
   ,JoinType (..)
   ,SelectList (..)
   ,SelectItem (..)
   ,CopySource (..)
   ,AttributeDef (..)
   ,RowConstraint (..)
   ,AlterTableAction(..)
   ,Constraint (..)
   ,TypeAttributeDef (..)
   ,ParamDef (..)
   ,VarDef (..)
   ,RaiseType (..)
   ,CombineType (..)
   ,Volatility (..)
   ,Language (..)
   ,TypeName (..)
   ,DropType (..)
   ,Cascade (..)
   ,Direction (..)
   ,Distinct (..)
   ,Natural (..)
   ,IfExists (..)
   ,RestartIdentity (..)
   ,Expression (..)
   ,FrameClause(..)
   ,InList (..)
   ,LiftFlavour(..)
   ,TriggerWhen(..)
   ,TriggerEvent(..)
   ,TriggerFire(..)
   ,StatementList
   ,ExpressionListStatementListPairList
   ,ExpressionListStatementListPair
   ,ExpressionList
   ,StringList
   ,ParamDefList
   ,AttributeDefList
   ,ConstraintList
   ,TypeAttributeDefList
   ,TypeNameList
   ,StringTypeNameListPair
   ,StringTypeNameListPairList
   ,ExpressionStatementListPairList
   ,SetClauseList
   ,CaseExpressionListExpressionPairList
   ,MaybeExpression
   ,TableRefList
   ,ExpressionListList
   ,SelectItemList
   ,OnExpr
   ,RowConstraintList
   ,VarDefList
   ,ExpressionStatementListPair
   ,CaseExpressionListExpressionPair
   ,CaseExpressionList
   ,ExpressionDirectionPair
   ,ExpressionDirectionPairList
   ,MaybeBoolExpression
   ,MaybeSelectList
   ,SetValue(..)
   -- typechecking
   ,typeCheck
   ,typeCheckPS
   ,typeCheckExpression
) where

import Data.Maybe
import Data.List
import Debug.Trace
import Control.Monad.Error
import Control.Arrow
import Data.Either
import Control.Applicative
import Data.Generics
import Data.Char

import Database.HsSqlPpp.AstInternals.TypeType
import Database.HsSqlPpp.AstInternals.TypeChecking.TypeConversion
import Database.HsSqlPpp.AstInternals.TypeChecking.ErrorUtils
import Database.HsSqlPpp.AstInternals.AstAnnotation
import Database.HsSqlPpp.AstInternals.Environment.EnvironmentInternal
import Database.HsSqlPpp.AstInternals.Environment.LocalIdentifierBindings
import Database.HsSqlPpp.AstInternals.Environment.DefaultTemplate1Environment
import Database.HsSqlPpp.Utils
import Data.Generics.PlateData


{-# LINE 683 "AstInternal.ag" #-}

{-
-- | Type check multiple asts, allowing type checking references in
--   later files to definitions in earlier files. This is probably
--   more straightforward if you parse the files then concatenate the
--   statementlists together before type checking rather than using
--   this function
typeCheckMany :: Environment -> [StatementList] -> [StatementList]
typeCheckMany env sts =
    annInt env sts []
    where
      annInt e (s:ss) ress =
          let (e1,res) = typeCheck e s
          in annInt e1 ss (res:ress)
      annInt _ [] ress = reverse ress
-}

-- | Takes an ast, checks against catalog passed, and adds
--   annotations, including types, type errors, and statement info.
--   Returns the updated catalog as well as the annotated ast.
typeCheck :: Environment -> StatementList -> (Environment,StatementList)
typeCheck env sts =
    let t = sem_Root (Root (fixupImplicitJoins sts))
        ta = wrap_Root t Inh_Root {env_Inh_Root = env
                                  ,lib_Inh_Root = emptyBindings}
        tl = annotatedTree_Syn_Root ta
        env1 = producedEnv_Syn_Root ta
   in case tl of
         Root r -> (env1,r)

-- | Unfinished version of type check which can type check an
-- individual statement with ? or positional arg placeholders in
-- it. Will error if the statement isn't select, update, insert or
-- delete. For use in type checking embedded parameterized
-- statements. Does all typechecking and annotation that the regular
-- typecheck does.
typeCheckPS :: Environment -> Statement -> Either String Statement
typeCheckPS env st =
    case st of
      SelectStatement _ _ -> tc
      Insert _ _ _ _ _ -> tc
      Update _ _ _ _ _ -> tc
      Delete _ _ _ _ -> tc
      _ -> Left "requires select, update, insert or delete statement"
    where
      tc = let t = sem_Root (Root (fixupImplicitJoins [st]))
               ta = wrap_Root t Inh_Root {env_Inh_Root = env
                                         ,lib_Inh_Root = emptyBindings}
               tl = annotatedTree_Syn_Root ta
               env1 = producedEnv_Syn_Root ta
           in case tl of
                Root [st1] -> Right st1
                _ -> error "impossible happened in typeCheckPS!"


-- | Testing utility, mainly used to check an expression for type errors
-- or to get its type.
typeCheckExpression :: Environment -> Expression -> Expression
typeCheckExpression env ex =
    let t = sem_ExpressionRoot (ExpressionRoot (fixupImplicitJoins ex))
        rt = (annotatedTree_Syn_ExpressionRoot
              (wrap_ExpressionRoot t Inh_ExpressionRoot {env_Inh_ExpressionRoot = env
                                                        ,lib_Inh_ExpressionRoot = emptyBindings}))
    in case rt of
         ExpressionRoot e -> e

{-
bit of a hack, to avoid rewriting the tableref type checking to be
able to do implicit joins, we just convert them in to the equivalent
explicit join
-}

fixupImplicitJoins :: Data a => a -> a
fixupImplicitJoins =
    transformBi $ \x ->
            case x of
              -- alter asts to change implicit joins into explicit joins
              Select an dis sl trs@(_:_:_) whr grp hav ord lim off
                  -> Select an dis sl [convTrefs trs] whr grp hav ord lim off
              x1 -> x1
    where
      convTrefs (tr:tr1:trs) = JoinedTref [] tr Unnatural Cross (convTrefs (tr1:trs)) Nothing NoAlias
      convTrefs (tr:[]) = tr
      convTrefs _ = error "failed doing implicit join fixup hack"

{-# LINE 190 "AstInternal.hs" #-}

{-# LINE 81 "./TypeChecking/Misc.ag" #-}

{-
================================================================================

= couple of small utils

I think this should be alright, an identifier referenced in an
expression can only have zero or one dot in it.
-}

splitIdentifier :: String -> (String,String)
splitIdentifier s = let (a,b) = span (/= '.') s
                    in if b == ""
                         then ("", a)
                         else (a,tail b)

{-
helper to make adding annotations a bit easier
-}

annTypesAndErrors :: Data a => a -> Type -> [TypeError]
                  -> Maybe [AnnotationElement] -> a
annTypesAndErrors item nt errs add =
    updateAnnotation modifier item
    where
      modifier = (([TypeAnnotation nt] ++ fromMaybe [] add ++
       map TypeErrorA errs) ++)

{-
================================================================================

proper dodgy:
1st pass is to add inferred types to the tree. This is done only for
expressions in a funcall argument list atm. Then we pull out the
placeholders after they've had this information added. Only the
placeholders in funcall argument lists will have their type inferred
in this way, to be expanded.

This should probably be done during the typechecking phase instead,
but probably needs a proper type inferencing algorithm to be used, is
done like this for development expediency.

-}
getPlaceholders :: Data a => a -> [Expression]
getPlaceholders st =
    filter isPlaceholder $ everything (++) (mkQ [] ga) (setInferredTypes st)
    where
      ga :: Expression -> [Expression]
      ga s = [s]
      isPlaceholder e = case e of
                          PositionalArg _ _ -> True
                          Placeholder _ -> True
                          _ -> False

getPlaceholderTypes :: Data a => a -> [Type]
getPlaceholderTypes ex =
    map (getInferredType . getAnnotation) $ getPlaceholders ex
    where
      getInferredType (InferredType t:_) = t
      getInferredType (_:as) = getInferredType as
      getInferredType [] = TypeCheckFailed


setInferredTypes :: Data a => a -> a
setInferredTypes =
     transformBi $ \x ->
       case x of
         FunCall an op exprs
                -> FunCall an op (addInferredTypes an exprs)
         x1 -> x1
     where
       addInferredTypes an exprs =
           let args1 = fmap (\(_,a,_,_) -> a) $ fp an
               args = fromMaybe [] args1
               fargs = args ++ repeat TypeCheckFailed
           in flip map (zip exprs fargs)
                  (\(ex, ty) -> updateAnnotation (++ [InferredType ty]) ex)
           where
             fp (FunctionPrototypeA f:_) = Just f
             fp (_:ls) = fp ls
             fp [] = Nothing


{-# LINE 276 "AstInternal.hs" #-}

{-# LINE 94 "./TypeChecking/Expressions.ag" #-}

{-

small shim in front of findCallMatch in the type conversion code, to
handle some special cases.

Some of the special cases will no longer be needed when variadic
support is added.

between, greatest and least are treated as syntactic sugar so we
delegate the function lookups to the <=/>= operators.

the row comparison should be more general than this, since it supports
any operator satisfying some properties


TODO: move all of this into find call match. Don't know why it's separate
-}
typeCheckFunCall :: Environment -> String -> [Type] -> Either [TypeError] FunctionPrototype
typeCheckFunCall env fnName' argsType =
    {-trace ("typecheckfncall " ++ fnName' ++ show argsType) $-}
    --dependsOnRTpe argsType $
      case fnName of
              "count" -> -- not quite sure how this is suppose to work,
                         -- the counts in the pg catalog accept either
                         -- no args, or one arg of type any, but you can call
                         -- count with multiple arguments?
                         return ("count", argsType, typeBigInt, False)
              "!between" -> do
                    f1 <- lookupReturnType ">=" [argsType !! 0, argsType !! 1]
                    f2 <- lookupReturnType "<=" [argsType !! 0, argsType !! 2]
                    lookupFn "!and" [f1,f2]
              "greatest" -> do
                    fp@(_,_,t,_) <- lookupFn fnName argsType
                    lookupFn ">=" [t,t]
                    return fp
              "least" -> do
                    fp@(_,_,t,_) <- lookupFn fnName argsType
                    lookupFn "<=" [t,t]
                    return fp
              "!rowctor" -> return $ ("!rowCtor", argsType, AnonymousRecordType argsType, False)
                    -- special case the row comparison ops
                    -- this needs to be fixed: we want to match
                    -- any implicit casts to functions on composite types
                    -- first, then we can use the anonymous record type on
                    -- any composite
              _ | fnName `elem` ["=", "<>", "<=", ">=", "<", ">"]
                         && length argsType == 2
                         && all isCompositeOrSetOfCompositeType argsType
                         && compositesCompatible env (head argsType) (head $ tail argsType) -> return (fnName, argsType, typeBool, False)
              --checked for all special cases, so run general case now
              s -> lookupFn s argsType
    where
      lookupReturnType :: String -> [Type] -> Either [TypeError] Type
      lookupReturnType s1 args = fmap (\(_,_,r,_) -> r) $ lookupFn s1 args
      lookupFn :: String -> [Type] -> Either [TypeError] FunctionPrototype
      lookupFn s1 args = findCallMatch env
                             (if s1 == "u-" then "-" else s1) args
      fnName = map toLower fnName'
{-# LINE 338 "AstInternal.hs" #-}

{-# LINE 138 "./TypeChecking/SelectStatement.ag" #-}


typeCheckValuesExpr :: Environment -> [[Type]] -> Either [TypeError] Type
typeCheckValuesExpr env rowsTs =
        let colNames = zipWith (++)
                           (repeat "column")
                           (map show [1..length $ head rowsTs])
        in unionRelTypes env rowsTs colNames


typeCheckCombineSelect :: Environment -> Type -> Type -> Either [TypeError] Type
typeCheckCombineSelect env v1 v2 = do
    u1 <- unwrapSetOfComposite v1
    let colNames = map fst u1
    u2 <- unwrapSetOfComposite v2
    let colTypes1 = map snd u1
    let colTypes2 = map snd u2
    unionRelTypes env [colTypes1,colTypes2] colNames

unionRelTypes :: Environment -> [[Type]] -> [String] -> Either [TypeError] Type
unionRelTypes env rowsTs colNames =
  let lengths = map length rowsTs
  in case () of
             _ | null rowsTs ->
                   Left [NoRowsGivenForValues]
               | not (all (==head lengths) lengths) ->
                   Left [ValuesListsMustBeSameLength]
               | otherwise ->
                   --i don't think this propagates all the errors, just the first set
                   mapM (resolveResultSetType env) (transpose rowsTs) >>=
                     (return . SetOfType . CompositeType . zip colNames)

{-# LINE 373 "AstInternal.hs" #-}

{-# LINE 200 "./TypeChecking/TableRefs.ag" #-}

{-
convert a function call into a [String,[(string,type)]] list for use
in a tableref context
first consideration is the alias: if there is an alias in the select,
e.g. select * from generate_series(1,2) x;  (alias is x)
we use that, otherwise we use the name of the function
second consideration is the attributes coming out, roughly speaking
we have to convert an arbitrary type to a relation type
if we have a relation valued function, we don't need to do anything
if we have a setof non composite, we lift the single type to an
attribute, using the function name for the attribute name
if we have a non setof, we lift the single type to an attribute and
then relation, using the function name for the attribute name
need to check to see what should happen with arrayof

-}
funIdens :: Environment -> String -> Expression -> Either [TypeError] (String,[(String,Type)])
funIdens env alias fnVal = do
   errorWhen (case fnVal of
                FunCall _ _ _ -> False
                _ -> True)
             [ContextError "FunCall"]
   let (FunCall _ fnName _) = fnVal
       correlationName = if alias /= ""
                           then alias
                           else fnName
   attrs <- do
     case getTypeAnnotation fnVal of
       SetOfType (NamedCompositeType t) -> envCompositePublicAttrs env [] t
       SetOfType x -> return [(correlationName,x)]
       y -> return [(correlationName,y)]
   return (correlationName, attrs)

getAlias :: String -> TableAlias -> String
getAlias def alias =
  case alias of
    NoAlias -> def
    TableAlias t -> t
    FullAlias t _ -> t

{-# LINE 417 "AstInternal.hs" #-}

{-# LINE 92 "./TypeChecking/SelectLists.ag" #-}

expandStar :: LocalIdentifierBindings
           -> String
           -> Type
           -> [(String,Type)]
           -> [(String,Type)]
expandStar env colName colType types =
    fromRight types $ do
    let (correlationName,iden) = splitIdentifier colName
    newCols <- if iden == "*"
                 then libExpandStar env correlationName
                 else return [(iden, colType)]
    return $ newCols ++ types

fixStar :: Expression -> Expression
fixStar =
    everywhere (mkT fixStar')
    where
      fixStar' :: Annotation -> Annotation
      fixStar' a =
          if TypeAnnotation TypeCheckFailed `elem` a
              && any (\an ->
                       case an of
                         TypeErrorA (UnrecognisedIdentifier x) |
                           let (_,iden) = splitIdentifier x
                           in iden == "*" -> True
                         _ -> False) a
             then filter (\an -> case an of
                                   TypeAnnotation TypeCheckFailed -> False
                                   TypeErrorA (UnrecognisedIdentifier _) -> False
                                   _ -> True) a
             else a
{-# LINE 452 "AstInternal.hs" #-}

{-# LINE 136 "./TypeChecking/Dml.ag" #-}

getRowTypes :: [Type] -> [Type]
getRowTypes [AnonymousRecordType ts] = ts
getRowTypes ts = ts
{-# LINE 459 "AstInternal.hs" #-}

{-# LINE 174 "./TypeChecking/Dml.ag" #-}


--small shortcut to help produce better errors?
checkRelationExists :: Environment -> String -> Either [TypeError] ()
checkRelationExists env tbl =
    envCompositeDef env relationComposites tbl >>
    return ()

--used by both insert and update
checkColumnConsistency :: Environment ->  String -> [String] -> [(String,Type)]
                       -> Either [TypeError] [(String,Type)]
checkColumnConsistency env tbl cols' insNameTypePairs = trace ("ccc " ++ show insNameTypePairs ++ "\n") $ do
  ttcols <- lowerize <$> envCompositePublicAttrs env [] tbl
  let cols = if null cols'
               then map fst ttcols
               else map (map toLower) cols'
  errorWhen (length insNameTypePairs /= length cols) [WrongNumberOfColumns]
  let nonMatchingColumns = cols \\ map fst ttcols
  errorWhen (not $ null nonMatchingColumns) $
       map UnrecognisedIdentifier nonMatchingColumns
  let targetNameTypePairs = map (\l -> (l,fromJust $ lookup l ttcols)) cols
        --check the types of the insdata match the column targets
        --name datatype columntype
      typeTriples = map (\((a,b),c) -> (a,b,c)) $
                    zip targetNameTypePairs $
                    map snd insNameTypePairs
      errs :: [TypeError]
      errs = concat $ lefts $
             map (\(_,b,c) -> checkAssignmentValid env c b) typeTriples
  liftErrors errs
  return targetNameTypePairs
  where
    lowerize = map (\(a,b) -> (map toLower a,b))

{-# LINE 496 "AstInternal.hs" #-}

{-# LINE 40 "./TypeChecking/CreateTable.ag" #-}

defaultSystemColumns :: [(String,Type)]
defaultSystemColumns = [("tableoid", ScalarType "oid")
                       ,("cmax", ScalarType "cid")
                       ,("xmax", ScalarType "xid")
                       ,("cmin", ScalarType "cid")
                       ,("xmin", ScalarType "xid")
                       ,("ctid", ScalarType "tid")]
{-# LINE 507 "AstInternal.hs" #-}
-- AlterTableAction --------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative AddConstraint:
         child ann            : {Annotation}
         child con            : Constraint 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative AlterColumnDefault:
         child ann            : {Annotation}
         child nm             : {String}
         child def            : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data AlterTableAction  = AddConstraint (Annotation) (Constraint) 
                       | AlterColumnDefault (Annotation) (String) (Expression) 
                       deriving ( Data,Eq,Show,Typeable)
-- cata
sem_AlterTableAction :: AlterTableAction  ->
                        T_AlterTableAction 
sem_AlterTableAction (AddConstraint _ann _con )  =
    (sem_AlterTableAction_AddConstraint _ann (sem_Constraint _con ) )
sem_AlterTableAction (AlterColumnDefault _ann _nm _def )  =
    (sem_AlterTableAction_AlterColumnDefault _ann _nm (sem_Expression _def ) )
-- semantic domain
type T_AlterTableAction  = Environment ->
                           LocalIdentifierBindings ->
                           ( AlterTableAction,AlterTableAction)
data Inh_AlterTableAction  = Inh_AlterTableAction {env_Inh_AlterTableAction :: Environment,lib_Inh_AlterTableAction :: LocalIdentifierBindings}
data Syn_AlterTableAction  = Syn_AlterTableAction {annotatedTree_Syn_AlterTableAction :: AlterTableAction,originalTree_Syn_AlterTableAction :: AlterTableAction}
wrap_AlterTableAction :: T_AlterTableAction  ->
                         Inh_AlterTableAction  ->
                         Syn_AlterTableAction 
wrap_AlterTableAction sem (Inh_AlterTableAction _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_AlterTableAction _lhsOannotatedTree _lhsOoriginalTree ))
sem_AlterTableAction_AddConstraint :: Annotation ->
                                      T_Constraint  ->
                                      T_AlterTableAction 
sem_AlterTableAction_AddConstraint ann_ con_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: AlterTableAction
              _lhsOoriginalTree :: AlterTableAction
              _conOenv :: Environment
              _conOlib :: LocalIdentifierBindings
              _conIannotatedTree :: Constraint
              _conIoriginalTree :: Constraint
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  AddConstraint ann_ _conIannotatedTree
                  {-# LINE 571 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  AddConstraint ann_ _conIoriginalTree
                  {-# LINE 576 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 581 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 586 "AstInternal.hs" #-}
              -- copy rule (down)
              _conOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 591 "AstInternal.hs" #-}
              -- copy rule (down)
              _conOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 596 "AstInternal.hs" #-}
              ( _conIannotatedTree,_conIoriginalTree) =
                  (con_ _conOenv _conOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_AlterTableAction_AlterColumnDefault :: Annotation ->
                                           String ->
                                           T_Expression  ->
                                           T_AlterTableAction 
sem_AlterTableAction_AlterColumnDefault ann_ nm_ def_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: AlterTableAction
              _lhsOoriginalTree :: AlterTableAction
              _defOenv :: Environment
              _defOlib :: LocalIdentifierBindings
              _defIannotatedTree :: Expression
              _defIliftedColumnName :: String
              _defIoriginalTree :: Expression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  AlterColumnDefault ann_ nm_ _defIannotatedTree
                  {-# LINE 618 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  AlterColumnDefault ann_ nm_ _defIoriginalTree
                  {-# LINE 623 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 628 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 633 "AstInternal.hs" #-}
              -- copy rule (down)
              _defOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 638 "AstInternal.hs" #-}
              -- copy rule (down)
              _defOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 643 "AstInternal.hs" #-}
              ( _defIannotatedTree,_defIliftedColumnName,_defIoriginalTree) =
                  (def_ _defOenv _defOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- AttributeDef ------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         attrName             : String
         namedType            : Type
         originalTree         : SELF 
   alternatives:
      alternative AttributeDef:
         child ann            : {Annotation}
         child name           : {String}
         child typ            : TypeName 
         child def            : MaybeExpression 
         child cons           : RowConstraintList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data AttributeDef  = AttributeDef (Annotation) (String) (TypeName) (MaybeExpression) (RowConstraintList) 
                   deriving ( Data,Eq,Show,Typeable)
-- cata
sem_AttributeDef :: AttributeDef  ->
                    T_AttributeDef 
sem_AttributeDef (AttributeDef _ann _name _typ _def _cons )  =
    (sem_AttributeDef_AttributeDef _ann _name (sem_TypeName _typ ) (sem_MaybeExpression _def ) (sem_RowConstraintList _cons ) )
-- semantic domain
type T_AttributeDef  = Environment ->
                       LocalIdentifierBindings ->
                       ( AttributeDef,String,Type,AttributeDef)
data Inh_AttributeDef  = Inh_AttributeDef {env_Inh_AttributeDef :: Environment,lib_Inh_AttributeDef :: LocalIdentifierBindings}
data Syn_AttributeDef  = Syn_AttributeDef {annotatedTree_Syn_AttributeDef :: AttributeDef,attrName_Syn_AttributeDef :: String,namedType_Syn_AttributeDef :: Type,originalTree_Syn_AttributeDef :: AttributeDef}
wrap_AttributeDef :: T_AttributeDef  ->
                     Inh_AttributeDef  ->
                     Syn_AttributeDef 
wrap_AttributeDef sem (Inh_AttributeDef _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOattrName,_lhsOnamedType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_AttributeDef _lhsOannotatedTree _lhsOattrName _lhsOnamedType _lhsOoriginalTree ))
sem_AttributeDef_AttributeDef :: Annotation ->
                                 String ->
                                 T_TypeName  ->
                                 T_MaybeExpression  ->
                                 T_RowConstraintList  ->
                                 T_AttributeDef 
sem_AttributeDef_AttributeDef ann_ name_ typ_ def_ cons_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOattrName :: String
              _lhsOnamedType :: Type
              _consOlib :: LocalIdentifierBindings
              _lhsOannotatedTree :: AttributeDef
              _lhsOoriginalTree :: AttributeDef
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _defOenv :: Environment
              _defOlib :: LocalIdentifierBindings
              _consOenv :: Environment
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              _defIannotatedTree :: MaybeExpression
              _defIoriginalTree :: MaybeExpression
              _consIannotatedTree :: RowConstraintList
              _consIoriginalTree :: RowConstraintList
              -- "./TypeChecking/CreateTable.ag"(line 79, column 9)
              _lhsOattrName =
                  {-# LINE 79 "./TypeChecking/CreateTable.ag" #-}
                  map toLower name_
                  {-# LINE 719 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 80, column 9)
              _lhsOnamedType =
                  {-# LINE 80 "./TypeChecking/CreateTable.ag" #-}
                  _typInamedType
                  {-# LINE 724 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 95, column 9)
              _consOlib =
                  {-# LINE 95 "./TypeChecking/CreateTable.ag" #-}
                  case updateBindings _lhsIlib _lhsIenv
                           [LibStackIDs [("", [(name_, _typInamedType)])]] of
                    Left x -> error $ show x
                    Right e -> e
                  {-# LINE 732 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  AttributeDef ann_ name_ _typIannotatedTree _defIannotatedTree _consIannotatedTree
                  {-# LINE 737 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  AttributeDef ann_ name_ _typIoriginalTree _defIoriginalTree _consIoriginalTree
                  {-# LINE 742 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 747 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 752 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 757 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 762 "AstInternal.hs" #-}
              -- copy rule (down)
              _defOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 767 "AstInternal.hs" #-}
              -- copy rule (down)
              _defOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 772 "AstInternal.hs" #-}
              -- copy rule (down)
              _consOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 777 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
              ( _defIannotatedTree,_defIoriginalTree) =
                  (def_ _defOenv _defOlib )
              ( _consIannotatedTree,_consIoriginalTree) =
                  (cons_ _consOenv _consOlib )
          in  ( _lhsOannotatedTree,_lhsOattrName,_lhsOnamedType,_lhsOoriginalTree)))
-- AttributeDefList --------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         attrs                : [(String, Type)]
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : AttributeDef 
         child tl             : AttributeDefList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type AttributeDefList  = [(AttributeDef)]
-- cata
sem_AttributeDefList :: AttributeDefList  ->
                        T_AttributeDefList 
sem_AttributeDefList list  =
    (Prelude.foldr sem_AttributeDefList_Cons sem_AttributeDefList_Nil (Prelude.map sem_AttributeDef list) )
-- semantic domain
type T_AttributeDefList  = Environment ->
                           LocalIdentifierBindings ->
                           ( AttributeDefList,([(String, Type)]),AttributeDefList)
data Inh_AttributeDefList  = Inh_AttributeDefList {env_Inh_AttributeDefList :: Environment,lib_Inh_AttributeDefList :: LocalIdentifierBindings}
data Syn_AttributeDefList  = Syn_AttributeDefList {annotatedTree_Syn_AttributeDefList :: AttributeDefList,attrs_Syn_AttributeDefList :: [(String, Type)],originalTree_Syn_AttributeDefList :: AttributeDefList}
wrap_AttributeDefList :: T_AttributeDefList  ->
                         Inh_AttributeDefList  ->
                         Syn_AttributeDefList 
wrap_AttributeDefList sem (Inh_AttributeDefList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOattrs,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_AttributeDefList _lhsOannotatedTree _lhsOattrs _lhsOoriginalTree ))
sem_AttributeDefList_Cons :: T_AttributeDef  ->
                             T_AttributeDefList  ->
                             T_AttributeDefList 
sem_AttributeDefList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOattrs :: ([(String, Type)])
              _lhsOannotatedTree :: AttributeDefList
              _lhsOoriginalTree :: AttributeDefList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: AttributeDef
              _hdIattrName :: String
              _hdInamedType :: Type
              _hdIoriginalTree :: AttributeDef
              _tlIannotatedTree :: AttributeDefList
              _tlIattrs :: ([(String, Type)])
              _tlIoriginalTree :: AttributeDefList
              -- "./TypeChecking/CreateTable.ag"(line 85, column 12)
              _lhsOattrs =
                  {-# LINE 85 "./TypeChecking/CreateTable.ag" #-}
                  (_hdIattrName, _hdInamedType) : _tlIattrs
                  {-# LINE 850 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 855 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 860 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 865 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 870 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 875 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 880 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 885 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 890 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIattrName,_hdInamedType,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIattrs,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOattrs,_lhsOoriginalTree)))
sem_AttributeDefList_Nil :: T_AttributeDefList 
sem_AttributeDefList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOattrs :: ([(String, Type)])
              _lhsOannotatedTree :: AttributeDefList
              _lhsOoriginalTree :: AttributeDefList
              -- "./TypeChecking/CreateTable.ag"(line 86, column 11)
              _lhsOattrs =
                  {-# LINE 86 "./TypeChecking/CreateTable.ag" #-}
                  []
                  {-# LINE 907 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 912 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 917 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 922 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 927 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOattrs,_lhsOoriginalTree)))
-- Cascade -----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cascade:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Restrict:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Cascade  = Cascade 
              | Restrict 
              deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Cascade :: Cascade  ->
               T_Cascade 
sem_Cascade (Cascade )  =
    (sem_Cascade_Cascade )
sem_Cascade (Restrict )  =
    (sem_Cascade_Restrict )
-- semantic domain
type T_Cascade  = Environment ->
                  LocalIdentifierBindings ->
                  ( Cascade,Cascade)
data Inh_Cascade  = Inh_Cascade {env_Inh_Cascade :: Environment,lib_Inh_Cascade :: LocalIdentifierBindings}
data Syn_Cascade  = Syn_Cascade {annotatedTree_Syn_Cascade :: Cascade,originalTree_Syn_Cascade :: Cascade}
wrap_Cascade :: T_Cascade  ->
                Inh_Cascade  ->
                Syn_Cascade 
wrap_Cascade sem (Inh_Cascade _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Cascade _lhsOannotatedTree _lhsOoriginalTree ))
sem_Cascade_Cascade :: T_Cascade 
sem_Cascade_Cascade  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Cascade
              _lhsOoriginalTree :: Cascade
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Cascade
                  {-# LINE 981 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Cascade
                  {-# LINE 986 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 991 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 996 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Cascade_Restrict :: T_Cascade 
sem_Cascade_Restrict  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Cascade
              _lhsOoriginalTree :: Cascade
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Restrict
                  {-# LINE 1008 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Restrict
                  {-# LINE 1013 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1018 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1023 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- CaseExpressionList ------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : Expression 
         child tl             : CaseExpressionList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type CaseExpressionList  = [(Expression)]
-- cata
sem_CaseExpressionList :: CaseExpressionList  ->
                          T_CaseExpressionList 
sem_CaseExpressionList list  =
    (Prelude.foldr sem_CaseExpressionList_Cons sem_CaseExpressionList_Nil (Prelude.map sem_Expression list) )
-- semantic domain
type T_CaseExpressionList  = Environment ->
                             LocalIdentifierBindings ->
                             ( CaseExpressionList,CaseExpressionList)
data Inh_CaseExpressionList  = Inh_CaseExpressionList {env_Inh_CaseExpressionList :: Environment,lib_Inh_CaseExpressionList :: LocalIdentifierBindings}
data Syn_CaseExpressionList  = Syn_CaseExpressionList {annotatedTree_Syn_CaseExpressionList :: CaseExpressionList,originalTree_Syn_CaseExpressionList :: CaseExpressionList}
wrap_CaseExpressionList :: T_CaseExpressionList  ->
                           Inh_CaseExpressionList  ->
                           Syn_CaseExpressionList 
wrap_CaseExpressionList sem (Inh_CaseExpressionList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_CaseExpressionList _lhsOannotatedTree _lhsOoriginalTree ))
sem_CaseExpressionList_Cons :: T_Expression  ->
                               T_CaseExpressionList  ->
                               T_CaseExpressionList 
sem_CaseExpressionList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CaseExpressionList
              _lhsOoriginalTree :: CaseExpressionList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: Expression
              _hdIliftedColumnName :: String
              _hdIoriginalTree :: Expression
              _tlIannotatedTree :: CaseExpressionList
              _tlIoriginalTree :: CaseExpressionList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 1086 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 1091 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1096 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1101 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1106 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1111 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1116 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1121 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIliftedColumnName,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_CaseExpressionList_Nil :: T_CaseExpressionList 
sem_CaseExpressionList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CaseExpressionList
              _lhsOoriginalTree :: CaseExpressionList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 1137 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 1142 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1147 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1152 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- CaseExpressionListExpressionPair ----------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Tuple:
         child x1             : CaseExpressionList 
         child x2             : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type CaseExpressionListExpressionPair  = ( (CaseExpressionList),(Expression))
-- cata
sem_CaseExpressionListExpressionPair :: CaseExpressionListExpressionPair  ->
                                        T_CaseExpressionListExpressionPair 
sem_CaseExpressionListExpressionPair ( x1,x2)  =
    (sem_CaseExpressionListExpressionPair_Tuple (sem_CaseExpressionList x1 ) (sem_Expression x2 ) )
-- semantic domain
type T_CaseExpressionListExpressionPair  = Environment ->
                                           LocalIdentifierBindings ->
                                           ( CaseExpressionListExpressionPair,CaseExpressionListExpressionPair)
data Inh_CaseExpressionListExpressionPair  = Inh_CaseExpressionListExpressionPair {env_Inh_CaseExpressionListExpressionPair :: Environment,lib_Inh_CaseExpressionListExpressionPair :: LocalIdentifierBindings}
data Syn_CaseExpressionListExpressionPair  = Syn_CaseExpressionListExpressionPair {annotatedTree_Syn_CaseExpressionListExpressionPair :: CaseExpressionListExpressionPair,originalTree_Syn_CaseExpressionListExpressionPair :: CaseExpressionListExpressionPair}
wrap_CaseExpressionListExpressionPair :: T_CaseExpressionListExpressionPair  ->
                                         Inh_CaseExpressionListExpressionPair  ->
                                         Syn_CaseExpressionListExpressionPair 
wrap_CaseExpressionListExpressionPair sem (Inh_CaseExpressionListExpressionPair _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_CaseExpressionListExpressionPair _lhsOannotatedTree _lhsOoriginalTree ))
sem_CaseExpressionListExpressionPair_Tuple :: T_CaseExpressionList  ->
                                              T_Expression  ->
                                              T_CaseExpressionListExpressionPair 
sem_CaseExpressionListExpressionPair_Tuple x1_ x2_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CaseExpressionListExpressionPair
              _lhsOoriginalTree :: CaseExpressionListExpressionPair
              _x1Oenv :: Environment
              _x1Olib :: LocalIdentifierBindings
              _x2Oenv :: Environment
              _x2Olib :: LocalIdentifierBindings
              _x1IannotatedTree :: CaseExpressionList
              _x1IoriginalTree :: CaseExpressionList
              _x2IannotatedTree :: Expression
              _x2IliftedColumnName :: String
              _x2IoriginalTree :: Expression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IannotatedTree,_x2IannotatedTree)
                  {-# LINE 1211 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IoriginalTree,_x2IoriginalTree)
                  {-# LINE 1216 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1221 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1226 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1231 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1236 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1241 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1246 "AstInternal.hs" #-}
              ( _x1IannotatedTree,_x1IoriginalTree) =
                  (x1_ _x1Oenv _x1Olib )
              ( _x2IannotatedTree,_x2IliftedColumnName,_x2IoriginalTree) =
                  (x2_ _x2Oenv _x2Olib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- CaseExpressionListExpressionPairList ------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : CaseExpressionListExpressionPair 
         child tl             : CaseExpressionListExpressionPairList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type CaseExpressionListExpressionPairList  = [(CaseExpressionListExpressionPair)]
-- cata
sem_CaseExpressionListExpressionPairList :: CaseExpressionListExpressionPairList  ->
                                            T_CaseExpressionListExpressionPairList 
sem_CaseExpressionListExpressionPairList list  =
    (Prelude.foldr sem_CaseExpressionListExpressionPairList_Cons sem_CaseExpressionListExpressionPairList_Nil (Prelude.map sem_CaseExpressionListExpressionPair list) )
-- semantic domain
type T_CaseExpressionListExpressionPairList  = Environment ->
                                               LocalIdentifierBindings ->
                                               ( CaseExpressionListExpressionPairList,CaseExpressionListExpressionPairList)
data Inh_CaseExpressionListExpressionPairList  = Inh_CaseExpressionListExpressionPairList {env_Inh_CaseExpressionListExpressionPairList :: Environment,lib_Inh_CaseExpressionListExpressionPairList :: LocalIdentifierBindings}
data Syn_CaseExpressionListExpressionPairList  = Syn_CaseExpressionListExpressionPairList {annotatedTree_Syn_CaseExpressionListExpressionPairList :: CaseExpressionListExpressionPairList,originalTree_Syn_CaseExpressionListExpressionPairList :: CaseExpressionListExpressionPairList}
wrap_CaseExpressionListExpressionPairList :: T_CaseExpressionListExpressionPairList  ->
                                             Inh_CaseExpressionListExpressionPairList  ->
                                             Syn_CaseExpressionListExpressionPairList 
wrap_CaseExpressionListExpressionPairList sem (Inh_CaseExpressionListExpressionPairList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_CaseExpressionListExpressionPairList _lhsOannotatedTree _lhsOoriginalTree ))
sem_CaseExpressionListExpressionPairList_Cons :: T_CaseExpressionListExpressionPair  ->
                                                 T_CaseExpressionListExpressionPairList  ->
                                                 T_CaseExpressionListExpressionPairList 
sem_CaseExpressionListExpressionPairList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CaseExpressionListExpressionPairList
              _lhsOoriginalTree :: CaseExpressionListExpressionPairList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: CaseExpressionListExpressionPair
              _hdIoriginalTree :: CaseExpressionListExpressionPair
              _tlIannotatedTree :: CaseExpressionListExpressionPairList
              _tlIoriginalTree :: CaseExpressionListExpressionPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 1312 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 1317 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1322 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1327 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1332 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1337 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1342 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1347 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_CaseExpressionListExpressionPairList_Nil :: T_CaseExpressionListExpressionPairList 
sem_CaseExpressionListExpressionPairList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CaseExpressionListExpressionPairList
              _lhsOoriginalTree :: CaseExpressionListExpressionPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 1363 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 1368 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1373 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1378 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- CombineType -------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Except:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Intersect:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Union:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative UnionAll:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data CombineType  = Except 
                  | Intersect 
                  | Union 
                  | UnionAll 
                  deriving ( Data,Eq,Show,Typeable)
-- cata
sem_CombineType :: CombineType  ->
                   T_CombineType 
sem_CombineType (Except )  =
    (sem_CombineType_Except )
sem_CombineType (Intersect )  =
    (sem_CombineType_Intersect )
sem_CombineType (Union )  =
    (sem_CombineType_Union )
sem_CombineType (UnionAll )  =
    (sem_CombineType_UnionAll )
-- semantic domain
type T_CombineType  = Environment ->
                      LocalIdentifierBindings ->
                      ( CombineType,CombineType)
data Inh_CombineType  = Inh_CombineType {env_Inh_CombineType :: Environment,lib_Inh_CombineType :: LocalIdentifierBindings}
data Syn_CombineType  = Syn_CombineType {annotatedTree_Syn_CombineType :: CombineType,originalTree_Syn_CombineType :: CombineType}
wrap_CombineType :: T_CombineType  ->
                    Inh_CombineType  ->
                    Syn_CombineType 
wrap_CombineType sem (Inh_CombineType _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_CombineType _lhsOannotatedTree _lhsOoriginalTree ))
sem_CombineType_Except :: T_CombineType 
sem_CombineType_Except  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CombineType
              _lhsOoriginalTree :: CombineType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Except
                  {-# LINE 1446 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Except
                  {-# LINE 1451 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1456 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1461 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_CombineType_Intersect :: T_CombineType 
sem_CombineType_Intersect  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CombineType
              _lhsOoriginalTree :: CombineType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Intersect
                  {-# LINE 1473 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Intersect
                  {-# LINE 1478 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1483 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1488 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_CombineType_Union :: T_CombineType 
sem_CombineType_Union  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CombineType
              _lhsOoriginalTree :: CombineType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Union
                  {-# LINE 1500 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Union
                  {-# LINE 1505 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1510 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1515 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_CombineType_UnionAll :: T_CombineType 
sem_CombineType_UnionAll  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CombineType
              _lhsOoriginalTree :: CombineType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  UnionAll
                  {-# LINE 1527 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  UnionAll
                  {-# LINE 1532 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1537 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1542 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- Constraint --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative CheckConstraint:
         child ann            : {Annotation}
         child name           : {String}
         child expression     : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative PrimaryKeyConstraint:
         child ann            : {Annotation}
         child name           : {String}
         child stringList     : StringList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative ReferenceConstraint:
         child ann            : {Annotation}
         child name           : {String}
         child atts           : StringList 
         child table          : {String}
         child tableAtts      : StringList 
         child onUpdate       : Cascade 
         child onDelete       : Cascade 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative UniqueConstraint:
         child ann            : {Annotation}
         child name           : {String}
         child stringList     : StringList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Constraint  = CheckConstraint (Annotation) (String) (Expression) 
                 | PrimaryKeyConstraint (Annotation) (String) (StringList) 
                 | ReferenceConstraint (Annotation) (String) (StringList) (String) (StringList) (Cascade) (Cascade) 
                 | UniqueConstraint (Annotation) (String) (StringList) 
                 deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Constraint :: Constraint  ->
                  T_Constraint 
sem_Constraint (CheckConstraint _ann _name _expression )  =
    (sem_Constraint_CheckConstraint _ann _name (sem_Expression _expression ) )
sem_Constraint (PrimaryKeyConstraint _ann _name _stringList )  =
    (sem_Constraint_PrimaryKeyConstraint _ann _name (sem_StringList _stringList ) )
sem_Constraint (ReferenceConstraint _ann _name _atts _table _tableAtts _onUpdate _onDelete )  =
    (sem_Constraint_ReferenceConstraint _ann _name (sem_StringList _atts ) _table (sem_StringList _tableAtts ) (sem_Cascade _onUpdate ) (sem_Cascade _onDelete ) )
sem_Constraint (UniqueConstraint _ann _name _stringList )  =
    (sem_Constraint_UniqueConstraint _ann _name (sem_StringList _stringList ) )
-- semantic domain
type T_Constraint  = Environment ->
                     LocalIdentifierBindings ->
                     ( Constraint,Constraint)
data Inh_Constraint  = Inh_Constraint {env_Inh_Constraint :: Environment,lib_Inh_Constraint :: LocalIdentifierBindings}
data Syn_Constraint  = Syn_Constraint {annotatedTree_Syn_Constraint :: Constraint,originalTree_Syn_Constraint :: Constraint}
wrap_Constraint :: T_Constraint  ->
                   Inh_Constraint  ->
                   Syn_Constraint 
wrap_Constraint sem (Inh_Constraint _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Constraint _lhsOannotatedTree _lhsOoriginalTree ))
sem_Constraint_CheckConstraint :: Annotation ->
                                  String ->
                                  T_Expression  ->
                                  T_Constraint 
sem_Constraint_CheckConstraint ann_ name_ expression_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Constraint
              _lhsOoriginalTree :: Constraint
              _expressionOenv :: Environment
              _expressionOlib :: LocalIdentifierBindings
              _expressionIannotatedTree :: Expression
              _expressionIliftedColumnName :: String
              _expressionIoriginalTree :: Expression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CheckConstraint ann_ name_ _expressionIannotatedTree
                  {-# LINE 1634 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CheckConstraint ann_ name_ _expressionIoriginalTree
                  {-# LINE 1639 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1644 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1649 "AstInternal.hs" #-}
              -- copy rule (down)
              _expressionOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1654 "AstInternal.hs" #-}
              -- copy rule (down)
              _expressionOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1659 "AstInternal.hs" #-}
              ( _expressionIannotatedTree,_expressionIliftedColumnName,_expressionIoriginalTree) =
                  (expression_ _expressionOenv _expressionOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Constraint_PrimaryKeyConstraint :: Annotation ->
                                       String ->
                                       T_StringList  ->
                                       T_Constraint 
sem_Constraint_PrimaryKeyConstraint ann_ name_ stringList_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Constraint
              _lhsOoriginalTree :: Constraint
              _stringListOenv :: Environment
              _stringListOlib :: LocalIdentifierBindings
              _stringListIannotatedTree :: StringList
              _stringListIoriginalTree :: StringList
              _stringListIstrings :: ([String])
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  PrimaryKeyConstraint ann_ name_ _stringListIannotatedTree
                  {-# LINE 1681 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  PrimaryKeyConstraint ann_ name_ _stringListIoriginalTree
                  {-# LINE 1686 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1691 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1696 "AstInternal.hs" #-}
              -- copy rule (down)
              _stringListOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1701 "AstInternal.hs" #-}
              -- copy rule (down)
              _stringListOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1706 "AstInternal.hs" #-}
              ( _stringListIannotatedTree,_stringListIoriginalTree,_stringListIstrings) =
                  (stringList_ _stringListOenv _stringListOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Constraint_ReferenceConstraint :: Annotation ->
                                      String ->
                                      T_StringList  ->
                                      String ->
                                      T_StringList  ->
                                      T_Cascade  ->
                                      T_Cascade  ->
                                      T_Constraint 
sem_Constraint_ReferenceConstraint ann_ name_ atts_ table_ tableAtts_ onUpdate_ onDelete_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Constraint
              _lhsOoriginalTree :: Constraint
              _attsOenv :: Environment
              _attsOlib :: LocalIdentifierBindings
              _tableAttsOenv :: Environment
              _tableAttsOlib :: LocalIdentifierBindings
              _onUpdateOenv :: Environment
              _onUpdateOlib :: LocalIdentifierBindings
              _onDeleteOenv :: Environment
              _onDeleteOlib :: LocalIdentifierBindings
              _attsIannotatedTree :: StringList
              _attsIoriginalTree :: StringList
              _attsIstrings :: ([String])
              _tableAttsIannotatedTree :: StringList
              _tableAttsIoriginalTree :: StringList
              _tableAttsIstrings :: ([String])
              _onUpdateIannotatedTree :: Cascade
              _onUpdateIoriginalTree :: Cascade
              _onDeleteIannotatedTree :: Cascade
              _onDeleteIoriginalTree :: Cascade
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ReferenceConstraint ann_ name_ _attsIannotatedTree table_ _tableAttsIannotatedTree _onUpdateIannotatedTree _onDeleteIannotatedTree
                  {-# LINE 1745 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ReferenceConstraint ann_ name_ _attsIoriginalTree table_ _tableAttsIoriginalTree _onUpdateIoriginalTree _onDeleteIoriginalTree
                  {-# LINE 1750 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1755 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1760 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1765 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1770 "AstInternal.hs" #-}
              -- copy rule (down)
              _tableAttsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1775 "AstInternal.hs" #-}
              -- copy rule (down)
              _tableAttsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1780 "AstInternal.hs" #-}
              -- copy rule (down)
              _onUpdateOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1785 "AstInternal.hs" #-}
              -- copy rule (down)
              _onUpdateOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1790 "AstInternal.hs" #-}
              -- copy rule (down)
              _onDeleteOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1795 "AstInternal.hs" #-}
              -- copy rule (down)
              _onDeleteOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1800 "AstInternal.hs" #-}
              ( _attsIannotatedTree,_attsIoriginalTree,_attsIstrings) =
                  (atts_ _attsOenv _attsOlib )
              ( _tableAttsIannotatedTree,_tableAttsIoriginalTree,_tableAttsIstrings) =
                  (tableAtts_ _tableAttsOenv _tableAttsOlib )
              ( _onUpdateIannotatedTree,_onUpdateIoriginalTree) =
                  (onUpdate_ _onUpdateOenv _onUpdateOlib )
              ( _onDeleteIannotatedTree,_onDeleteIoriginalTree) =
                  (onDelete_ _onDeleteOenv _onDeleteOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Constraint_UniqueConstraint :: Annotation ->
                                   String ->
                                   T_StringList  ->
                                   T_Constraint 
sem_Constraint_UniqueConstraint ann_ name_ stringList_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Constraint
              _lhsOoriginalTree :: Constraint
              _stringListOenv :: Environment
              _stringListOlib :: LocalIdentifierBindings
              _stringListIannotatedTree :: StringList
              _stringListIoriginalTree :: StringList
              _stringListIstrings :: ([String])
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  UniqueConstraint ann_ name_ _stringListIannotatedTree
                  {-# LINE 1828 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  UniqueConstraint ann_ name_ _stringListIoriginalTree
                  {-# LINE 1833 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1838 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1843 "AstInternal.hs" #-}
              -- copy rule (down)
              _stringListOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1848 "AstInternal.hs" #-}
              -- copy rule (down)
              _stringListOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1853 "AstInternal.hs" #-}
              ( _stringListIannotatedTree,_stringListIoriginalTree,_stringListIstrings) =
                  (stringList_ _stringListOenv _stringListOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ConstraintList ----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : Constraint 
         child tl             : ConstraintList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ConstraintList  = [(Constraint)]
-- cata
sem_ConstraintList :: ConstraintList  ->
                      T_ConstraintList 
sem_ConstraintList list  =
    (Prelude.foldr sem_ConstraintList_Cons sem_ConstraintList_Nil (Prelude.map sem_Constraint list) )
-- semantic domain
type T_ConstraintList  = Environment ->
                         LocalIdentifierBindings ->
                         ( ConstraintList,ConstraintList)
data Inh_ConstraintList  = Inh_ConstraintList {env_Inh_ConstraintList :: Environment,lib_Inh_ConstraintList :: LocalIdentifierBindings}
data Syn_ConstraintList  = Syn_ConstraintList {annotatedTree_Syn_ConstraintList :: ConstraintList,originalTree_Syn_ConstraintList :: ConstraintList}
wrap_ConstraintList :: T_ConstraintList  ->
                       Inh_ConstraintList  ->
                       Syn_ConstraintList 
wrap_ConstraintList sem (Inh_ConstraintList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ConstraintList _lhsOannotatedTree _lhsOoriginalTree ))
sem_ConstraintList_Cons :: T_Constraint  ->
                           T_ConstraintList  ->
                           T_ConstraintList 
sem_ConstraintList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ConstraintList
              _lhsOoriginalTree :: ConstraintList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: Constraint
              _hdIoriginalTree :: Constraint
              _tlIannotatedTree :: ConstraintList
              _tlIoriginalTree :: ConstraintList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 1917 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 1922 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1927 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1932 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1937 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1942 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 1947 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 1952 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_ConstraintList_Nil :: T_ConstraintList 
sem_ConstraintList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ConstraintList
              _lhsOoriginalTree :: ConstraintList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 1968 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 1973 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 1978 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 1983 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- CopySource --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative CopyFilename:
         child string         : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Stdin:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data CopySource  = CopyFilename (String) 
                 | Stdin 
                 deriving ( Data,Eq,Show,Typeable)
-- cata
sem_CopySource :: CopySource  ->
                  T_CopySource 
sem_CopySource (CopyFilename _string )  =
    (sem_CopySource_CopyFilename _string )
sem_CopySource (Stdin )  =
    (sem_CopySource_Stdin )
-- semantic domain
type T_CopySource  = Environment ->
                     LocalIdentifierBindings ->
                     ( CopySource,CopySource)
data Inh_CopySource  = Inh_CopySource {env_Inh_CopySource :: Environment,lib_Inh_CopySource :: LocalIdentifierBindings}
data Syn_CopySource  = Syn_CopySource {annotatedTree_Syn_CopySource :: CopySource,originalTree_Syn_CopySource :: CopySource}
wrap_CopySource :: T_CopySource  ->
                   Inh_CopySource  ->
                   Syn_CopySource 
wrap_CopySource sem (Inh_CopySource _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_CopySource _lhsOannotatedTree _lhsOoriginalTree ))
sem_CopySource_CopyFilename :: String ->
                               T_CopySource 
sem_CopySource_CopyFilename string_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CopySource
              _lhsOoriginalTree :: CopySource
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CopyFilename string_
                  {-# LINE 2039 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CopyFilename string_
                  {-# LINE 2044 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2049 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2054 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_CopySource_Stdin :: T_CopySource 
sem_CopySource_Stdin  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: CopySource
              _lhsOoriginalTree :: CopySource
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Stdin
                  {-# LINE 2066 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Stdin
                  {-# LINE 2071 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2076 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2081 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- Direction ---------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Asc:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Desc:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Direction  = Asc 
                | Desc 
                deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Direction :: Direction  ->
                 T_Direction 
sem_Direction (Asc )  =
    (sem_Direction_Asc )
sem_Direction (Desc )  =
    (sem_Direction_Desc )
-- semantic domain
type T_Direction  = Environment ->
                    LocalIdentifierBindings ->
                    ( Direction,Direction)
data Inh_Direction  = Inh_Direction {env_Inh_Direction :: Environment,lib_Inh_Direction :: LocalIdentifierBindings}
data Syn_Direction  = Syn_Direction {annotatedTree_Syn_Direction :: Direction,originalTree_Syn_Direction :: Direction}
wrap_Direction :: T_Direction  ->
                  Inh_Direction  ->
                  Syn_Direction 
wrap_Direction sem (Inh_Direction _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Direction _lhsOannotatedTree _lhsOoriginalTree ))
sem_Direction_Asc :: T_Direction 
sem_Direction_Asc  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Direction
              _lhsOoriginalTree :: Direction
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Asc
                  {-# LINE 2135 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Asc
                  {-# LINE 2140 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2145 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2150 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Direction_Desc :: T_Direction 
sem_Direction_Desc  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Direction
              _lhsOoriginalTree :: Direction
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Desc
                  {-# LINE 2162 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Desc
                  {-# LINE 2167 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2172 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2177 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- Distinct ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Distinct:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Dupes:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Distinct  = Distinct 
               | Dupes 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Distinct :: Distinct  ->
                T_Distinct 
sem_Distinct (Distinct )  =
    (sem_Distinct_Distinct )
sem_Distinct (Dupes )  =
    (sem_Distinct_Dupes )
-- semantic domain
type T_Distinct  = Environment ->
                   LocalIdentifierBindings ->
                   ( Distinct,Distinct)
data Inh_Distinct  = Inh_Distinct {env_Inh_Distinct :: Environment,lib_Inh_Distinct :: LocalIdentifierBindings}
data Syn_Distinct  = Syn_Distinct {annotatedTree_Syn_Distinct :: Distinct,originalTree_Syn_Distinct :: Distinct}
wrap_Distinct :: T_Distinct  ->
                 Inh_Distinct  ->
                 Syn_Distinct 
wrap_Distinct sem (Inh_Distinct _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Distinct _lhsOannotatedTree _lhsOoriginalTree ))
sem_Distinct_Distinct :: T_Distinct 
sem_Distinct_Distinct  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Distinct
              _lhsOoriginalTree :: Distinct
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Distinct
                  {-# LINE 2231 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Distinct
                  {-# LINE 2236 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2241 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2246 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Distinct_Dupes :: T_Distinct 
sem_Distinct_Dupes  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Distinct
              _lhsOoriginalTree :: Distinct
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Dupes
                  {-# LINE 2258 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Dupes
                  {-# LINE 2263 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2268 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2273 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- DropType ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Domain:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Table:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Type:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative View:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data DropType  = Domain 
               | Table 
               | Type 
               | View 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_DropType :: DropType  ->
                T_DropType 
sem_DropType (Domain )  =
    (sem_DropType_Domain )
sem_DropType (Table )  =
    (sem_DropType_Table )
sem_DropType (Type )  =
    (sem_DropType_Type )
sem_DropType (View )  =
    (sem_DropType_View )
-- semantic domain
type T_DropType  = Environment ->
                   LocalIdentifierBindings ->
                   ( DropType,DropType)
data Inh_DropType  = Inh_DropType {env_Inh_DropType :: Environment,lib_Inh_DropType :: LocalIdentifierBindings}
data Syn_DropType  = Syn_DropType {annotatedTree_Syn_DropType :: DropType,originalTree_Syn_DropType :: DropType}
wrap_DropType :: T_DropType  ->
                 Inh_DropType  ->
                 Syn_DropType 
wrap_DropType sem (Inh_DropType _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_DropType _lhsOannotatedTree _lhsOoriginalTree ))
sem_DropType_Domain :: T_DropType 
sem_DropType_Domain  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: DropType
              _lhsOoriginalTree :: DropType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Domain
                  {-# LINE 2341 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Domain
                  {-# LINE 2346 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2351 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2356 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_DropType_Table :: T_DropType 
sem_DropType_Table  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: DropType
              _lhsOoriginalTree :: DropType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Table
                  {-# LINE 2368 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Table
                  {-# LINE 2373 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2378 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2383 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_DropType_Type :: T_DropType 
sem_DropType_Type  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: DropType
              _lhsOoriginalTree :: DropType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Type
                  {-# LINE 2395 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Type
                  {-# LINE 2400 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2405 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2410 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_DropType_View :: T_DropType 
sem_DropType_View  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: DropType
              _lhsOoriginalTree :: DropType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  View
                  {-# LINE 2422 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  View
                  {-# LINE 2427 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 2432 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2437 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- Expression --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         liftedColumnName     : String
         originalTree         : SELF 
   alternatives:
      alternative BooleanLit:
         child ann            : {Annotation}
         child b              : {Bool}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Case:
         child ann            : {Annotation}
         child cases          : CaseExpressionListExpressionPairList 
         child els            : MaybeExpression 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local whenTypes   : _
            local thenTypes   : _
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative CaseSimple:
         child ann            : {Annotation}
         child value          : Expression 
         child cases          : CaseExpressionListExpressionPairList 
         child els            : MaybeExpression 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local whenTypes   : _
            local thenTypes   : _
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Cast:
         child ann            : {Annotation}
         child expr           : Expression 
         child tn             : TypeName 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Exists:
         child ann            : {Annotation}
         child sel            : SelectExpression 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative FloatLit:
         child ann            : {Annotation}
         child d              : {Double}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative FunCall:
         child ann            : {Annotation}
         child funName        : {String}
         child args           : ExpressionList 
         visit 0:
            local _tup1       : _
            local tpe         : _
            local prototype   : {Maybe FunctionPrototype}
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Identifier:
         child ann            : {Annotation}
         child i              : {String}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative InPredicate:
         child ann            : {Annotation}
         child expr           : Expression 
         child i              : {Bool}
         child list           : InList 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative IntegerLit:
         child ann            : {Annotation}
         child i              : {Integer}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative LiftOperator:
         child ann            : {Annotation}
         child oper           : {String}
         child flav           : LiftFlavour 
         child args           : ExpressionList 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative NullLit:
         child ann            : {Annotation}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Placeholder:
         child ann            : {Annotation}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative PositionalArg:
         child ann            : {Annotation}
         child p              : {Integer}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative ScalarSubQuery:
         child ann            : {Annotation}
         child sel            : SelectExpression 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative StringLit:
         child ann            : {Annotation}
         child quote          : {String}
         child value          : {String}
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative WindowFn:
         child ann            : {Annotation}
         child fn             : Expression 
         child partitionBy    : ExpressionList 
         child orderBy        : ExpressionList 
         child dir            : Direction 
         child frm            : FrameClause 
         visit 0:
            local prototype   : {Maybe FunctionPrototype}
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
-}
data Expression  = BooleanLit (Annotation) (Bool) 
                 | Case (Annotation) (CaseExpressionListExpressionPairList) (MaybeExpression) 
                 | CaseSimple (Annotation) (Expression) (CaseExpressionListExpressionPairList) (MaybeExpression) 
                 | Cast (Annotation) (Expression) (TypeName) 
                 | Exists (Annotation) (SelectExpression) 
                 | FloatLit (Annotation) (Double) 
                 | FunCall (Annotation) (String) (ExpressionList) 
                 | Identifier (Annotation) (String) 
                 | InPredicate (Annotation) (Expression) (Bool) (InList) 
                 | IntegerLit (Annotation) (Integer) 
                 | LiftOperator (Annotation) (String) (LiftFlavour) (ExpressionList) 
                 | NullLit (Annotation) 
                 | Placeholder (Annotation) 
                 | PositionalArg (Annotation) (Integer) 
                 | ScalarSubQuery (Annotation) (SelectExpression) 
                 | StringLit (Annotation) (String) (String) 
                 | WindowFn (Annotation) (Expression) (ExpressionList) (ExpressionList) (Direction) (FrameClause) 
                 deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Expression :: Expression  ->
                  T_Expression 
sem_Expression (BooleanLit _ann _b )  =
    (sem_Expression_BooleanLit _ann _b )
sem_Expression (Case _ann _cases _els )  =
    (sem_Expression_Case _ann (sem_CaseExpressionListExpressionPairList _cases ) (sem_MaybeExpression _els ) )
sem_Expression (CaseSimple _ann _value _cases _els )  =
    (sem_Expression_CaseSimple _ann (sem_Expression _value ) (sem_CaseExpressionListExpressionPairList _cases ) (sem_MaybeExpression _els ) )
sem_Expression (Cast _ann _expr _tn )  =
    (sem_Expression_Cast _ann (sem_Expression _expr ) (sem_TypeName _tn ) )
sem_Expression (Exists _ann _sel )  =
    (sem_Expression_Exists _ann (sem_SelectExpression _sel ) )
sem_Expression (FloatLit _ann _d )  =
    (sem_Expression_FloatLit _ann _d )
sem_Expression (FunCall _ann _funName _args )  =
    (sem_Expression_FunCall _ann _funName (sem_ExpressionList _args ) )
sem_Expression (Identifier _ann _i )  =
    (sem_Expression_Identifier _ann _i )
sem_Expression (InPredicate _ann _expr _i _list )  =
    (sem_Expression_InPredicate _ann (sem_Expression _expr ) _i (sem_InList _list ) )
sem_Expression (IntegerLit _ann _i )  =
    (sem_Expression_IntegerLit _ann _i )
sem_Expression (LiftOperator _ann _oper _flav _args )  =
    (sem_Expression_LiftOperator _ann _oper (sem_LiftFlavour _flav ) (sem_ExpressionList _args ) )
sem_Expression (NullLit _ann )  =
    (sem_Expression_NullLit _ann )
sem_Expression (Placeholder _ann )  =
    (sem_Expression_Placeholder _ann )
sem_Expression (PositionalArg _ann _p )  =
    (sem_Expression_PositionalArg _ann _p )
sem_Expression (ScalarSubQuery _ann _sel )  =
    (sem_Expression_ScalarSubQuery _ann (sem_SelectExpression _sel ) )
sem_Expression (StringLit _ann _quote _value )  =
    (sem_Expression_StringLit _ann _quote _value )
sem_Expression (WindowFn _ann _fn _partitionBy _orderBy _dir _frm )  =
    (sem_Expression_WindowFn _ann (sem_Expression _fn ) (sem_ExpressionList _partitionBy ) (sem_ExpressionList _orderBy ) (sem_Direction _dir ) (sem_FrameClause _frm ) )
-- semantic domain
type T_Expression  = Environment ->
                     LocalIdentifierBindings ->
                     ( Expression,String,Expression)
data Inh_Expression  = Inh_Expression {env_Inh_Expression :: Environment,lib_Inh_Expression :: LocalIdentifierBindings}
data Syn_Expression  = Syn_Expression {annotatedTree_Syn_Expression :: Expression,liftedColumnName_Syn_Expression :: String,originalTree_Syn_Expression :: Expression}
wrap_Expression :: T_Expression  ->
                   Inh_Expression  ->
                   Syn_Expression 
wrap_Expression sem (Inh_Expression _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Expression _lhsOannotatedTree _lhsOliftedColumnName _lhsOoriginalTree ))
sem_Expression_BooleanLit :: Annotation ->
                             Bool ->
                             T_Expression 
sem_Expression_BooleanLit ann_ b_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 2706 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 2711 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 41, column 19)
              _tpe =
                  {-# LINE 41 "./TypeChecking/Expressions.ag" #-}
                  Right typeBool
                  {-# LINE 2716 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 53, column 9)
              _backTree =
                  {-# LINE 53 "./TypeChecking/Expressions.ag" #-}
                  BooleanLit ann_ b_
                  {-# LINE 2721 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 2726 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  BooleanLit ann_ b_
                  {-# LINE 2731 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  BooleanLit ann_ b_
                  {-# LINE 2736 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2741 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_Case :: Annotation ->
                       T_CaseExpressionListExpressionPairList  ->
                       T_MaybeExpression  ->
                       T_Expression 
sem_Expression_Case ann_ cases_ els_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              _casesOenv :: Environment
              _casesOlib :: LocalIdentifierBindings
              _elsOenv :: Environment
              _elsOlib :: LocalIdentifierBindings
              _casesIannotatedTree :: CaseExpressionListExpressionPairList
              _casesIoriginalTree :: CaseExpressionListExpressionPairList
              _elsIannotatedTree :: MaybeExpression
              _elsIoriginalTree :: MaybeExpression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 2769 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 2774 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 202, column 9)
              _whenTypes =
                  {-# LINE 202 "./TypeChecking/Expressions.ag" #-}
                  map getTypeAnnotation $ concatMap fst $
                  _casesIannotatedTree
                  {-# LINE 2780 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 204, column 9)
              _thenTypes =
                  {-# LINE 204 "./TypeChecking/Expressions.ag" #-}
                  map getTypeAnnotation $
                      (map snd $ _casesIannotatedTree) ++
                        maybeToList _elsIannotatedTree
                  {-# LINE 2787 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 210, column 9)
              _tpe =
                  {-# LINE 210 "./TypeChecking/Expressions.ag" #-}
                  dependsOnRTpe _whenTypes     $ do
                  errorWhen (any (/= typeBool) _whenTypes    ) $
                            [WrongTypes typeBool _whenTypes    ]
                  dependsOnRTpe _thenTypes     $
                    resolveResultSetType _lhsIenv _thenTypes
                  {-# LINE 2796 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 216, column 9)
              _backTree =
                  {-# LINE 216 "./TypeChecking/Expressions.ag" #-}
                  Case ann_ _casesIannotatedTree _elsIannotatedTree
                  {-# LINE 2801 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 2806 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Case ann_ _casesIannotatedTree _elsIannotatedTree
                  {-# LINE 2811 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Case ann_ _casesIoriginalTree _elsIoriginalTree
                  {-# LINE 2816 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2821 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 2826 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 2831 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 2836 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 2841 "AstInternal.hs" #-}
              ( _casesIannotatedTree,_casesIoriginalTree) =
                  (cases_ _casesOenv _casesOlib )
              ( _elsIannotatedTree,_elsIoriginalTree) =
                  (els_ _elsOenv _elsOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_CaseSimple :: Annotation ->
                             T_Expression  ->
                             T_CaseExpressionListExpressionPairList  ->
                             T_MaybeExpression  ->
                             T_Expression 
sem_Expression_CaseSimple ann_ value_ cases_ els_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOoriginalTree :: Expression
              _lhsOliftedColumnName :: String
              _valueOenv :: Environment
              _valueOlib :: LocalIdentifierBindings
              _casesOenv :: Environment
              _casesOlib :: LocalIdentifierBindings
              _elsOenv :: Environment
              _elsOlib :: LocalIdentifierBindings
              _valueIannotatedTree :: Expression
              _valueIliftedColumnName :: String
              _valueIoriginalTree :: Expression
              _casesIannotatedTree :: CaseExpressionListExpressionPairList
              _casesIoriginalTree :: CaseExpressionListExpressionPairList
              _elsIannotatedTree :: MaybeExpression
              _elsIoriginalTree :: MaybeExpression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 2879 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 2884 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 202, column 9)
              _whenTypes =
                  {-# LINE 202 "./TypeChecking/Expressions.ag" #-}
                  map getTypeAnnotation $ concatMap fst $
                  _casesIannotatedTree
                  {-# LINE 2890 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 204, column 9)
              _thenTypes =
                  {-# LINE 204 "./TypeChecking/Expressions.ag" #-}
                  map getTypeAnnotation $
                      (map snd $ _casesIannotatedTree) ++
                        maybeToList _elsIannotatedTree
                  {-# LINE 2897 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 221, column 9)
              _tpe =
                  {-# LINE 221 "./TypeChecking/Expressions.ag" #-}
                  dependsOnRTpe _whenTypes     $ do
                  let valueType = getTypeAnnotation _valueIannotatedTree
                  checkWhenTypes <-
                      resolveResultSetType _lhsIenv (valueType : _whenTypes    )
                  dependsOnRTpe _thenTypes     $
                    resolveResultSetType _lhsIenv _thenTypes
                  {-# LINE 2907 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 228, column 9)
              _backTree =
                  {-# LINE 228 "./TypeChecking/Expressions.ag" #-}
                  CaseSimple ann_
                             _valueIannotatedTree
                             _casesIannotatedTree
                             _elsIannotatedTree
                  {-# LINE 2915 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CaseSimple ann_ _valueIannotatedTree _casesIannotatedTree _elsIannotatedTree
                  {-# LINE 2920 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CaseSimple ann_ _valueIoriginalTree _casesIoriginalTree _elsIoriginalTree
                  {-# LINE 2925 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 2930 "AstInternal.hs" #-}
              -- copy rule (up)
              _lhsOliftedColumnName =
                  {-# LINE 161 "./TypeChecking/SelectLists.ag" #-}
                  _valueIliftedColumnName
                  {-# LINE 2935 "AstInternal.hs" #-}
              -- copy rule (down)
              _valueOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 2940 "AstInternal.hs" #-}
              -- copy rule (down)
              _valueOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 2945 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 2950 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 2955 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 2960 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 2965 "AstInternal.hs" #-}
              ( _valueIannotatedTree,_valueIliftedColumnName,_valueIoriginalTree) =
                  (value_ _valueOenv _valueOlib )
              ( _casesIannotatedTree,_casesIoriginalTree) =
                  (cases_ _casesOenv _casesOlib )
              ( _elsIannotatedTree,_elsIoriginalTree) =
                  (els_ _elsOenv _elsOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_Cast :: Annotation ->
                       T_Expression  ->
                       T_TypeName  ->
                       T_Expression 
sem_Expression_Cast ann_ expr_ tn_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _tnOenv :: Environment
              _tnOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              _tnIannotatedTree :: TypeName
              _tnInamedType :: Type
              _tnIoriginalTree :: TypeName
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3001 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3006 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 66, column 12)
              _tpe =
                  {-# LINE 66 "./TypeChecking/Expressions.ag" #-}
                  Right $ _tnInamedType
                  {-# LINE 3011 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 67, column 12)
              _backTree =
                  {-# LINE 67 "./TypeChecking/Expressions.ag" #-}
                  Cast ann_ _exprIannotatedTree _tnIannotatedTree
                  {-# LINE 3016 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 169, column 10)
              _lhsOliftedColumnName =
                  {-# LINE 169 "./TypeChecking/SelectLists.ag" #-}
                  case _tnIannotatedTree of
                    SimpleTypeName _ tn -> tn
                    _ -> ""
                  {-# LINE 3023 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Cast ann_ _exprIannotatedTree _tnIannotatedTree
                  {-# LINE 3028 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Cast ann_ _exprIoriginalTree _tnIoriginalTree
                  {-# LINE 3033 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3038 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3043 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3048 "AstInternal.hs" #-}
              -- copy rule (down)
              _tnOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3053 "AstInternal.hs" #-}
              -- copy rule (down)
              _tnOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3058 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
              ( _tnIannotatedTree,_tnInamedType,_tnIoriginalTree) =
                  (tn_ _tnOenv _tnOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_Exists :: Annotation ->
                         T_SelectExpression  ->
                         T_Expression 
sem_Expression_Exists ann_ sel_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              _selOenv :: Environment
              _selOlib :: LocalIdentifierBindings
              _selIannotatedTree :: SelectExpression
              _selIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selIoriginalTree :: SelectExpression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3086 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3091 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 259, column 9)
              _tpe =
                  {-# LINE 259 "./TypeChecking/Expressions.ag" #-}
                  Right typeBool
                  {-# LINE 3096 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 260, column 9)
              _backTree =
                  {-# LINE 260 "./TypeChecking/Expressions.ag" #-}
                  Exists ann_ _selIannotatedTree
                  {-# LINE 3101 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3106 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Exists ann_ _selIannotatedTree
                  {-# LINE 3111 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Exists ann_ _selIoriginalTree
                  {-# LINE 3116 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3121 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3126 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3131 "AstInternal.hs" #-}
              ( _selIannotatedTree,_selIlibUpdates,_selIoriginalTree) =
                  (sel_ _selOenv _selOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_FloatLit :: Annotation ->
                           Double ->
                           T_Expression 
sem_Expression_FloatLit ann_ d_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3152 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3157 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 40, column 17)
              _tpe =
                  {-# LINE 40 "./TypeChecking/Expressions.ag" #-}
                  Right typeNumeric
                  {-# LINE 3162 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 51, column 9)
              _backTree =
                  {-# LINE 51 "./TypeChecking/Expressions.ag" #-}
                  FloatLit ann_ d_
                  {-# LINE 3167 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3172 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  FloatLit ann_ d_
                  {-# LINE 3177 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  FloatLit ann_ d_
                  {-# LINE 3182 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3187 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_FunCall :: Annotation ->
                          String ->
                          T_ExpressionList  ->
                          T_Expression 
sem_Expression_FunCall ann_ funName_ args_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              _argsOenv :: Environment
              _argsOlib :: LocalIdentifierBindings
              _argsIannotatedTree :: ExpressionList
              _argsIoriginalTree :: ExpressionList
              _argsItypeList :: ([Type])
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3212 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 74, column 9)
              __tup1 =
                  {-# LINE 74 "./TypeChecking/Expressions.ag" #-}
                  if any (==TypeCheckFailed) _argsItypeList
                  then (Right TypeCheckFailed, Nothing)
                  else
                    let fe = typeCheckFunCall
                             _lhsIenv
                             funName_
                             _argsItypeList
                    in (dependsOnRTpe _argsItypeList $ fmap (\(_,_,r,_) -> r) fe
                       ,eitherToMaybe fe)
                  {-# LINE 3225 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 74, column 9)
              (_tpe,_) =
                  {-# LINE 74 "./TypeChecking/Expressions.ag" #-}
                  __tup1
                  {-# LINE 3230 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 74, column 9)
              (_,_prototype) =
                  {-# LINE 74 "./TypeChecking/Expressions.ag" #-}
                  __tup1
                  {-# LINE 3235 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 83, column 9)
              _backTree =
                  {-# LINE 83 "./TypeChecking/Expressions.ag" #-}
                  FunCall ann_ funName_ _argsIannotatedTree
                  {-# LINE 3240 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 165, column 13)
              _lhsOliftedColumnName =
                  {-# LINE 165 "./TypeChecking/SelectLists.ag" #-}
                  if isOperatorName funName_
                     then ""
                     else funName_
                  {-# LINE 3247 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  FunCall ann_ funName_ _argsIannotatedTree
                  {-# LINE 3252 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  FunCall ann_ funName_ _argsIoriginalTree
                  {-# LINE 3257 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3262 "AstInternal.hs" #-}
              -- copy rule (down)
              _argsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3267 "AstInternal.hs" #-}
              -- copy rule (down)
              _argsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3272 "AstInternal.hs" #-}
              ( _argsIannotatedTree,_argsIoriginalTree,_argsItypeList) =
                  (args_ _argsOenv _argsOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_Identifier :: Annotation ->
                             String ->
                             T_Expression 
sem_Expression_Identifier ann_ i_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3293 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3298 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 241, column 9)
              _tpe =
                  {-# LINE 241 "./TypeChecking/Expressions.ag" #-}
                  libLookupID _lhsIlib i_
                  {-# LINE 3303 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 242, column 9)
              _backTree =
                  {-# LINE 242 "./TypeChecking/Expressions.ag" #-}
                  Identifier ann_ i_
                  {-# LINE 3308 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 164, column 16)
              _lhsOliftedColumnName =
                  {-# LINE 164 "./TypeChecking/SelectLists.ag" #-}
                  i_
                  {-# LINE 3313 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Identifier ann_ i_
                  {-# LINE 3318 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Identifier ann_ i_
                  {-# LINE 3323 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3328 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_InPredicate :: Annotation ->
                              T_Expression  ->
                              Bool ->
                              T_InList  ->
                              T_Expression 
sem_Expression_InPredicate ann_ expr_ i_ list_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOoriginalTree :: Expression
              _lhsOliftedColumnName :: String
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _listOenv :: Environment
              _listOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              _listIannotatedTree :: InList
              _listIlistType :: (Either [TypeError] Type)
              _listIoriginalTree :: InList
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3359 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3364 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 289, column 9)
              _tpe =
                  {-# LINE 289 "./TypeChecking/Expressions.ag" #-}
                  do
                  lt <- _listIlistType
                  ty <- resolveResultSetType
                            _lhsIenv
                            [getTypeAnnotation _exprIannotatedTree, lt]
                  return typeBool
                  {-# LINE 3374 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 295, column 9)
              _backTree =
                  {-# LINE 295 "./TypeChecking/Expressions.ag" #-}
                  InPredicate ann_
                              _exprIannotatedTree
                              i_
                              _listIannotatedTree
                  {-# LINE 3382 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  InPredicate ann_ _exprIannotatedTree i_ _listIannotatedTree
                  {-# LINE 3387 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  InPredicate ann_ _exprIoriginalTree i_ _listIoriginalTree
                  {-# LINE 3392 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3397 "AstInternal.hs" #-}
              -- copy rule (up)
              _lhsOliftedColumnName =
                  {-# LINE 161 "./TypeChecking/SelectLists.ag" #-}
                  _exprIliftedColumnName
                  {-# LINE 3402 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3407 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3412 "AstInternal.hs" #-}
              -- copy rule (down)
              _listOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3417 "AstInternal.hs" #-}
              -- copy rule (down)
              _listOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3422 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
              ( _listIannotatedTree,_listIlistType,_listIoriginalTree) =
                  (list_ _listOenv _listOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_IntegerLit :: Annotation ->
                             Integer ->
                             T_Expression 
sem_Expression_IntegerLit ann_ i_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3445 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3450 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 38, column 19)
              _tpe =
                  {-# LINE 38 "./TypeChecking/Expressions.ag" #-}
                  Right typeInt
                  {-# LINE 3455 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 47, column 9)
              _backTree =
                  {-# LINE 47 "./TypeChecking/Expressions.ag" #-}
                  IntegerLit ann_ i_
                  {-# LINE 3460 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3465 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  IntegerLit ann_ i_
                  {-# LINE 3470 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  IntegerLit ann_ i_
                  {-# LINE 3475 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3480 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_LiftOperator :: Annotation ->
                               String ->
                               T_LiftFlavour  ->
                               T_ExpressionList  ->
                               T_Expression 
sem_Expression_LiftOperator ann_ oper_ flav_ args_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              _flavOenv :: Environment
              _flavOlib :: LocalIdentifierBindings
              _argsOenv :: Environment
              _argsOlib :: LocalIdentifierBindings
              _flavIannotatedTree :: LiftFlavour
              _flavIoriginalTree :: LiftFlavour
              _argsIannotatedTree :: ExpressionList
              _argsIoriginalTree :: ExpressionList
              _argsItypeList :: ([Type])
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3510 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3515 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 167, column 9)
              _tpe =
                  {-# LINE 167 "./TypeChecking/Expressions.ag" #-}
                  dependsOnRTpe _argsItypeList $ do
                  let args = _argsIannotatedTree
                  errorWhen (length args /= 2)
                            [AnyAllError $ "must have two args, got " ++ show args]
                  let [a,b] = args
                      aType = getTypeAnnotation a
                      bType = getTypeAnnotation b
                  dependsOnRTpe [aType,bType] $ do
                  errorWhen (not $ isArrayType bType)
                            [AnyAllError $ "second arg must be array, got " ++ show args]
                  elemType <- unwrapArray $ bType
                  resType <- fmap (\(_,_,r,_) -> r) $ typeCheckFunCall
                                     _lhsIenv
                                     oper_
                                     [aType,elemType]
                  errorWhen (resType /= typeBool)
                            [AnyAllError $ "operator must have bool return, got " ++ show resType]
                  return resType
                  {-# LINE 3537 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 185, column 9)
              _backTree =
                  {-# LINE 185 "./TypeChecking/Expressions.ag" #-}
                  LiftOperator ann_ oper_ _flavIannotatedTree _argsIannotatedTree
                  {-# LINE 3542 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3547 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  LiftOperator ann_ oper_ _flavIannotatedTree _argsIannotatedTree
                  {-# LINE 3552 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  LiftOperator ann_ oper_ _flavIoriginalTree _argsIoriginalTree
                  {-# LINE 3557 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3562 "AstInternal.hs" #-}
              -- copy rule (down)
              _flavOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3567 "AstInternal.hs" #-}
              -- copy rule (down)
              _flavOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3572 "AstInternal.hs" #-}
              -- copy rule (down)
              _argsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3577 "AstInternal.hs" #-}
              -- copy rule (down)
              _argsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3582 "AstInternal.hs" #-}
              ( _flavIannotatedTree,_flavIoriginalTree) =
                  (flav_ _flavOenv _flavOlib )
              ( _argsIannotatedTree,_argsIoriginalTree,_argsItypeList) =
                  (args_ _argsOenv _argsOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_NullLit :: Annotation ->
                          T_Expression 
sem_Expression_NullLit ann_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3604 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3609 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 43, column 16)
              _tpe =
                  {-# LINE 43 "./TypeChecking/Expressions.ag" #-}
                  Right UnknownType
                  {-# LINE 3614 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 55, column 9)
              _backTree =
                  {-# LINE 55 "./TypeChecking/Expressions.ag" #-}
                  NullLit ann_
                  {-# LINE 3619 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3624 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  NullLit ann_
                  {-# LINE 3629 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  NullLit ann_
                  {-# LINE 3634 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3639 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_Placeholder :: Annotation ->
                              T_Expression 
sem_Expression_Placeholder ann_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3657 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3662 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 253, column 9)
              _tpe =
                  {-# LINE 253 "./TypeChecking/Expressions.ag" #-}
                  Right UnknownType
                  {-# LINE 3667 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 254, column 9)
              _backTree =
                  {-# LINE 254 "./TypeChecking/Expressions.ag" #-}
                  Placeholder ann_
                  {-# LINE 3672 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3677 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Placeholder ann_
                  {-# LINE 3682 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Placeholder ann_
                  {-# LINE 3687 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3692 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_PositionalArg :: Annotation ->
                                Integer ->
                                T_Expression 
sem_Expression_PositionalArg ann_ p_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3711 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3716 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 247, column 9)
              _tpe =
                  {-# LINE 247 "./TypeChecking/Expressions.ag" #-}
                  libLookupID _lhsIlib ('$':show p_)
                  {-# LINE 3721 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 248, column 9)
              _backTree =
                  {-# LINE 248 "./TypeChecking/Expressions.ag" #-}
                  PositionalArg ann_ p_
                  {-# LINE 3726 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3731 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  PositionalArg ann_ p_
                  {-# LINE 3736 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  PositionalArg ann_ p_
                  {-# LINE 3741 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3746 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_ScalarSubQuery :: Annotation ->
                                 T_SelectExpression  ->
                                 T_Expression 
sem_Expression_ScalarSubQuery ann_ sel_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              _selOenv :: Environment
              _selOlib :: LocalIdentifierBindings
              _selIannotatedTree :: SelectExpression
              _selIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selIoriginalTree :: SelectExpression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3770 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3775 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 271, column 9)
              _tpe =
                  {-# LINE 271 "./TypeChecking/Expressions.ag" #-}
                  do
                  let selType = getTypeAnnotation _selIannotatedTree
                  dependsOnRTpe [selType] $ do
                  f <- map snd <$> unwrapSetOfComposite selType
                  case length f of
                    0 -> Left [InternalError "no columns in scalar subquery?"]
                    1 -> Right $ head f
                    _ -> Right $ AnonymousRecordType f
                  {-# LINE 3787 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 281, column 9)
              _backTree =
                  {-# LINE 281 "./TypeChecking/Expressions.ag" #-}
                  ScalarSubQuery ann_ _selIannotatedTree
                  {-# LINE 3792 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3797 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ScalarSubQuery ann_ _selIannotatedTree
                  {-# LINE 3802 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ScalarSubQuery ann_ _selIoriginalTree
                  {-# LINE 3807 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3812 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3817 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3822 "AstInternal.hs" #-}
              ( _selIannotatedTree,_selIlibUpdates,_selIoriginalTree) =
                  (sel_ _selOenv _selOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_StringLit :: Annotation ->
                            String ->
                            String ->
                            T_Expression 
sem_Expression_StringLit ann_ quote_ value_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOliftedColumnName :: String
              _lhsOoriginalTree :: Expression
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3844 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3849 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 39, column 18)
              _tpe =
                  {-# LINE 39 "./TypeChecking/Expressions.ag" #-}
                  Right UnknownType
                  {-# LINE 3854 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 49, column 9)
              _backTree =
                  {-# LINE 49 "./TypeChecking/Expressions.ag" #-}
                  StringLit ann_ quote_ value_
                  {-# LINE 3859 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 177, column 7)
              _lhsOliftedColumnName =
                  {-# LINE 177 "./TypeChecking/SelectLists.ag" #-}
                  ""
                  {-# LINE 3864 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  StringLit ann_ quote_ value_
                  {-# LINE 3869 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  StringLit ann_ quote_ value_
                  {-# LINE 3874 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3879 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
sem_Expression_WindowFn :: Annotation ->
                           T_Expression  ->
                           T_ExpressionList  ->
                           T_ExpressionList  ->
                           T_Direction  ->
                           T_FrameClause  ->
                           T_Expression 
sem_Expression_WindowFn ann_ fn_ partitionBy_ orderBy_ dir_ frm_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Expression
              _prototype :: (Maybe FunctionPrototype)
              _lhsOoriginalTree :: Expression
              _lhsOliftedColumnName :: String
              _fnOenv :: Environment
              _fnOlib :: LocalIdentifierBindings
              _partitionByOenv :: Environment
              _partitionByOlib :: LocalIdentifierBindings
              _orderByOenv :: Environment
              _orderByOlib :: LocalIdentifierBindings
              _dirOenv :: Environment
              _dirOlib :: LocalIdentifierBindings
              _frmOenv :: Environment
              _frmOlib :: LocalIdentifierBindings
              _fnIannotatedTree :: Expression
              _fnIliftedColumnName :: String
              _fnIoriginalTree :: Expression
              _partitionByIannotatedTree :: ExpressionList
              _partitionByIoriginalTree :: ExpressionList
              _partitionByItypeList :: ([Type])
              _orderByIannotatedTree :: ExpressionList
              _orderByIoriginalTree :: ExpressionList
              _orderByItypeList :: ([Type])
              _dirIannotatedTree :: Direction
              _dirIoriginalTree :: Direction
              _frmIannotatedTree :: FrameClause
              _frmIoriginalTree :: FrameClause
              -- "./TypeChecking/Expressions.ag"(line 14, column 9)
              _lhsOannotatedTree =
                  {-# LINE 14 "./TypeChecking/Expressions.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ fmap ((:[]) . FunctionPrototypeA) _prototype
                  {-# LINE 3925 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 29, column 9)
              _prototype =
                  {-# LINE 29 "./TypeChecking/Expressions.ag" #-}
                  Nothing
                  {-# LINE 3930 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 87, column 9)
              _tpe =
                  {-# LINE 87 "./TypeChecking/Expressions.ag" #-}
                  Right (getTypeAnnotation _fnIannotatedTree)
                  {-# LINE 3935 "AstInternal.hs" #-}
              -- "./TypeChecking/Expressions.ag"(line 88, column 9)
              _backTree =
                  {-# LINE 88 "./TypeChecking/Expressions.ag" #-}
                  WindowFn ann_
                           _fnIannotatedTree
                           _partitionByIannotatedTree
                           _orderByIannotatedTree
                           _dirIannotatedTree
                           _frmIannotatedTree
                  {-# LINE 3945 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  WindowFn ann_ _fnIannotatedTree _partitionByIannotatedTree _orderByIannotatedTree _dirIannotatedTree _frmIannotatedTree
                  {-# LINE 3950 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  WindowFn ann_ _fnIoriginalTree _partitionByIoriginalTree _orderByIoriginalTree _dirIoriginalTree _frmIoriginalTree
                  {-# LINE 3955 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 3960 "AstInternal.hs" #-}
              -- copy rule (up)
              _lhsOliftedColumnName =
                  {-# LINE 161 "./TypeChecking/SelectLists.ag" #-}
                  _fnIliftedColumnName
                  {-# LINE 3965 "AstInternal.hs" #-}
              -- copy rule (down)
              _fnOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3970 "AstInternal.hs" #-}
              -- copy rule (down)
              _fnOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3975 "AstInternal.hs" #-}
              -- copy rule (down)
              _partitionByOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3980 "AstInternal.hs" #-}
              -- copy rule (down)
              _partitionByOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3985 "AstInternal.hs" #-}
              -- copy rule (down)
              _orderByOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 3990 "AstInternal.hs" #-}
              -- copy rule (down)
              _orderByOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 3995 "AstInternal.hs" #-}
              -- copy rule (down)
              _dirOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4000 "AstInternal.hs" #-}
              -- copy rule (down)
              _dirOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4005 "AstInternal.hs" #-}
              -- copy rule (down)
              _frmOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4010 "AstInternal.hs" #-}
              -- copy rule (down)
              _frmOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4015 "AstInternal.hs" #-}
              ( _fnIannotatedTree,_fnIliftedColumnName,_fnIoriginalTree) =
                  (fn_ _fnOenv _fnOlib )
              ( _partitionByIannotatedTree,_partitionByIoriginalTree,_partitionByItypeList) =
                  (partitionBy_ _partitionByOenv _partitionByOlib )
              ( _orderByIannotatedTree,_orderByIoriginalTree,_orderByItypeList) =
                  (orderBy_ _orderByOenv _orderByOlib )
              ( _dirIannotatedTree,_dirIoriginalTree) =
                  (dir_ _dirOenv _dirOlib )
              ( _frmIannotatedTree,_frmIoriginalTree) =
                  (frm_ _frmOenv _frmOlib )
          in  ( _lhsOannotatedTree,_lhsOliftedColumnName,_lhsOoriginalTree)))
-- ExpressionDirectionPair -------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Tuple:
         child x1             : Expression 
         child x2             : Direction 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionDirectionPair  = ( (Expression),(Direction))
-- cata
sem_ExpressionDirectionPair :: ExpressionDirectionPair  ->
                               T_ExpressionDirectionPair 
sem_ExpressionDirectionPair ( x1,x2)  =
    (sem_ExpressionDirectionPair_Tuple (sem_Expression x1 ) (sem_Direction x2 ) )
-- semantic domain
type T_ExpressionDirectionPair  = Environment ->
                                  LocalIdentifierBindings ->
                                  ( ExpressionDirectionPair,ExpressionDirectionPair)
data Inh_ExpressionDirectionPair  = Inh_ExpressionDirectionPair {env_Inh_ExpressionDirectionPair :: Environment,lib_Inh_ExpressionDirectionPair :: LocalIdentifierBindings}
data Syn_ExpressionDirectionPair  = Syn_ExpressionDirectionPair {annotatedTree_Syn_ExpressionDirectionPair :: ExpressionDirectionPair,originalTree_Syn_ExpressionDirectionPair :: ExpressionDirectionPair}
wrap_ExpressionDirectionPair :: T_ExpressionDirectionPair  ->
                                Inh_ExpressionDirectionPair  ->
                                Syn_ExpressionDirectionPair 
wrap_ExpressionDirectionPair sem (Inh_ExpressionDirectionPair _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionDirectionPair _lhsOannotatedTree _lhsOoriginalTree ))
sem_ExpressionDirectionPair_Tuple :: T_Expression  ->
                                     T_Direction  ->
                                     T_ExpressionDirectionPair 
sem_ExpressionDirectionPair_Tuple x1_ x2_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionDirectionPair
              _lhsOoriginalTree :: ExpressionDirectionPair
              _x1Oenv :: Environment
              _x1Olib :: LocalIdentifierBindings
              _x2Oenv :: Environment
              _x2Olib :: LocalIdentifierBindings
              _x1IannotatedTree :: Expression
              _x1IliftedColumnName :: String
              _x1IoriginalTree :: Expression
              _x2IannotatedTree :: Direction
              _x2IoriginalTree :: Direction
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IannotatedTree,_x2IannotatedTree)
                  {-# LINE 4084 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IoriginalTree,_x2IoriginalTree)
                  {-# LINE 4089 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4094 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4099 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4104 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4109 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4114 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4119 "AstInternal.hs" #-}
              ( _x1IannotatedTree,_x1IliftedColumnName,_x1IoriginalTree) =
                  (x1_ _x1Oenv _x1Olib )
              ( _x2IannotatedTree,_x2IoriginalTree) =
                  (x2_ _x2Oenv _x2Olib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ExpressionDirectionPairList ---------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : ExpressionDirectionPair 
         child tl             : ExpressionDirectionPairList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionDirectionPairList  = [(ExpressionDirectionPair)]
-- cata
sem_ExpressionDirectionPairList :: ExpressionDirectionPairList  ->
                                   T_ExpressionDirectionPairList 
sem_ExpressionDirectionPairList list  =
    (Prelude.foldr sem_ExpressionDirectionPairList_Cons sem_ExpressionDirectionPairList_Nil (Prelude.map sem_ExpressionDirectionPair list) )
-- semantic domain
type T_ExpressionDirectionPairList  = Environment ->
                                      LocalIdentifierBindings ->
                                      ( ExpressionDirectionPairList,ExpressionDirectionPairList)
data Inh_ExpressionDirectionPairList  = Inh_ExpressionDirectionPairList {env_Inh_ExpressionDirectionPairList :: Environment,lib_Inh_ExpressionDirectionPairList :: LocalIdentifierBindings}
data Syn_ExpressionDirectionPairList  = Syn_ExpressionDirectionPairList {annotatedTree_Syn_ExpressionDirectionPairList :: ExpressionDirectionPairList,originalTree_Syn_ExpressionDirectionPairList :: ExpressionDirectionPairList}
wrap_ExpressionDirectionPairList :: T_ExpressionDirectionPairList  ->
                                    Inh_ExpressionDirectionPairList  ->
                                    Syn_ExpressionDirectionPairList 
wrap_ExpressionDirectionPairList sem (Inh_ExpressionDirectionPairList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionDirectionPairList _lhsOannotatedTree _lhsOoriginalTree ))
sem_ExpressionDirectionPairList_Cons :: T_ExpressionDirectionPair  ->
                                        T_ExpressionDirectionPairList  ->
                                        T_ExpressionDirectionPairList 
sem_ExpressionDirectionPairList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionDirectionPairList
              _lhsOoriginalTree :: ExpressionDirectionPairList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: ExpressionDirectionPair
              _hdIoriginalTree :: ExpressionDirectionPair
              _tlIannotatedTree :: ExpressionDirectionPairList
              _tlIoriginalTree :: ExpressionDirectionPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 4185 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 4190 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4195 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4200 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4205 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4210 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4215 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4220 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_ExpressionDirectionPairList_Nil :: T_ExpressionDirectionPairList 
sem_ExpressionDirectionPairList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionDirectionPairList
              _lhsOoriginalTree :: ExpressionDirectionPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4236 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4241 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4246 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4251 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ExpressionList ----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         typeList             : [Type]
   alternatives:
      alternative Cons:
         child hd             : Expression 
         child tl             : ExpressionList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionList  = [(Expression)]
-- cata
sem_ExpressionList :: ExpressionList  ->
                      T_ExpressionList 
sem_ExpressionList list  =
    (Prelude.foldr sem_ExpressionList_Cons sem_ExpressionList_Nil (Prelude.map sem_Expression list) )
-- semantic domain
type T_ExpressionList  = Environment ->
                         LocalIdentifierBindings ->
                         ( ExpressionList,ExpressionList,([Type]))
data Inh_ExpressionList  = Inh_ExpressionList {env_Inh_ExpressionList :: Environment,lib_Inh_ExpressionList :: LocalIdentifierBindings}
data Syn_ExpressionList  = Syn_ExpressionList {annotatedTree_Syn_ExpressionList :: ExpressionList,originalTree_Syn_ExpressionList :: ExpressionList,typeList_Syn_ExpressionList :: [Type]}
wrap_ExpressionList :: T_ExpressionList  ->
                       Inh_ExpressionList  ->
                       Syn_ExpressionList 
wrap_ExpressionList sem (Inh_ExpressionList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOtypeList) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionList _lhsOannotatedTree _lhsOoriginalTree _lhsOtypeList ))
sem_ExpressionList_Cons :: T_Expression  ->
                           T_ExpressionList  ->
                           T_ExpressionList 
sem_ExpressionList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOtypeList :: ([Type])
              _lhsOannotatedTree :: ExpressionList
              _lhsOoriginalTree :: ExpressionList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: Expression
              _hdIliftedColumnName :: String
              _hdIoriginalTree :: Expression
              _tlIannotatedTree :: ExpressionList
              _tlIoriginalTree :: ExpressionList
              _tlItypeList :: ([Type])
              -- "./TypeChecking/Misc.ag"(line 52, column 12)
              _lhsOtypeList =
                  {-# LINE 52 "./TypeChecking/Misc.ag" #-}
                  getTypeAnnotation _hdIannotatedTree : _tlItypeList
                  {-# LINE 4317 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 4322 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 4327 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4332 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4337 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4342 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4347 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4352 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4357 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIliftedColumnName,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree,_tlItypeList) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOtypeList)))
sem_ExpressionList_Nil :: T_ExpressionList 
sem_ExpressionList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOtypeList :: ([Type])
              _lhsOannotatedTree :: ExpressionList
              _lhsOoriginalTree :: ExpressionList
              -- "./TypeChecking/Misc.ag"(line 53, column 11)
              _lhsOtypeList =
                  {-# LINE 53 "./TypeChecking/Misc.ag" #-}
                  []
                  {-# LINE 4374 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4379 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4384 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4389 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4394 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOtypeList)))
-- ExpressionListList ------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         typeListList         : [[Type]]
   alternatives:
      alternative Cons:
         child hd             : ExpressionList 
         child tl             : ExpressionListList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionListList  = [(ExpressionList)]
-- cata
sem_ExpressionListList :: ExpressionListList  ->
                          T_ExpressionListList 
sem_ExpressionListList list  =
    (Prelude.foldr sem_ExpressionListList_Cons sem_ExpressionListList_Nil (Prelude.map sem_ExpressionList list) )
-- semantic domain
type T_ExpressionListList  = Environment ->
                             LocalIdentifierBindings ->
                             ( ExpressionListList,ExpressionListList,([[Type]]))
data Inh_ExpressionListList  = Inh_ExpressionListList {env_Inh_ExpressionListList :: Environment,lib_Inh_ExpressionListList :: LocalIdentifierBindings}
data Syn_ExpressionListList  = Syn_ExpressionListList {annotatedTree_Syn_ExpressionListList :: ExpressionListList,originalTree_Syn_ExpressionListList :: ExpressionListList,typeListList_Syn_ExpressionListList :: [[Type]]}
wrap_ExpressionListList :: T_ExpressionListList  ->
                           Inh_ExpressionListList  ->
                           Syn_ExpressionListList 
wrap_ExpressionListList sem (Inh_ExpressionListList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOtypeListList) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionListList _lhsOannotatedTree _lhsOoriginalTree _lhsOtypeListList ))
sem_ExpressionListList_Cons :: T_ExpressionList  ->
                               T_ExpressionListList  ->
                               T_ExpressionListList 
sem_ExpressionListList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOtypeListList :: ([[Type]])
              _lhsOannotatedTree :: ExpressionListList
              _lhsOoriginalTree :: ExpressionListList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: ExpressionList
              _hdIoriginalTree :: ExpressionList
              _hdItypeList :: ([Type])
              _tlIannotatedTree :: ExpressionListList
              _tlIoriginalTree :: ExpressionListList
              _tlItypeListList :: ([[Type]])
              -- "./TypeChecking/Misc.ag"(line 59, column 12)
              _lhsOtypeListList =
                  {-# LINE 59 "./TypeChecking/Misc.ag" #-}
                  _hdItypeList : _tlItypeListList
                  {-# LINE 4460 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 4465 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 4470 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4475 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4480 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4485 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4490 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4495 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4500 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree,_hdItypeList) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree,_tlItypeListList) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOtypeListList)))
sem_ExpressionListList_Nil :: T_ExpressionListList 
sem_ExpressionListList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOtypeListList :: ([[Type]])
              _lhsOannotatedTree :: ExpressionListList
              _lhsOoriginalTree :: ExpressionListList
              -- "./TypeChecking/Misc.ag"(line 60, column 11)
              _lhsOtypeListList =
                  {-# LINE 60 "./TypeChecking/Misc.ag" #-}
                  []
                  {-# LINE 4517 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4522 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4527 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4532 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4537 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOtypeListList)))
-- ExpressionListStatementListPair -----------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Tuple:
         child x1             : ExpressionList 
         child x2             : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionListStatementListPair  = ( (ExpressionList),(StatementList))
-- cata
sem_ExpressionListStatementListPair :: ExpressionListStatementListPair  ->
                                       T_ExpressionListStatementListPair 
sem_ExpressionListStatementListPair ( x1,x2)  =
    (sem_ExpressionListStatementListPair_Tuple (sem_ExpressionList x1 ) (sem_StatementList x2 ) )
-- semantic domain
type T_ExpressionListStatementListPair  = Environment ->
                                          LocalIdentifierBindings ->
                                          ( ExpressionListStatementListPair,ExpressionListStatementListPair)
data Inh_ExpressionListStatementListPair  = Inh_ExpressionListStatementListPair {env_Inh_ExpressionListStatementListPair :: Environment,lib_Inh_ExpressionListStatementListPair :: LocalIdentifierBindings}
data Syn_ExpressionListStatementListPair  = Syn_ExpressionListStatementListPair {annotatedTree_Syn_ExpressionListStatementListPair :: ExpressionListStatementListPair,originalTree_Syn_ExpressionListStatementListPair :: ExpressionListStatementListPair}
wrap_ExpressionListStatementListPair :: T_ExpressionListStatementListPair  ->
                                        Inh_ExpressionListStatementListPair  ->
                                        Syn_ExpressionListStatementListPair 
wrap_ExpressionListStatementListPair sem (Inh_ExpressionListStatementListPair _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionListStatementListPair _lhsOannotatedTree _lhsOoriginalTree ))
sem_ExpressionListStatementListPair_Tuple :: T_ExpressionList  ->
                                             T_StatementList  ->
                                             T_ExpressionListStatementListPair 
sem_ExpressionListStatementListPair_Tuple x1_ x2_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _x2OenvUpdates :: ([EnvironmentUpdate])
              _x2OlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: ExpressionListStatementListPair
              _lhsOoriginalTree :: ExpressionListStatementListPair
              _x1Oenv :: Environment
              _x1Olib :: LocalIdentifierBindings
              _x2Oenv :: Environment
              _x2Olib :: LocalIdentifierBindings
              _x1IannotatedTree :: ExpressionList
              _x1IoriginalTree :: ExpressionList
              _x1ItypeList :: ([Type])
              _x2IannotatedTree :: StatementList
              _x2IoriginalTree :: StatementList
              _x2IproducedEnv :: Environment
              _x2IproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 94, column 9)
              _x2OenvUpdates =
                  {-# LINE 94 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 4600 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 95, column 9)
              _x2OlibUpdates =
                  {-# LINE 95 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 4605 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IannotatedTree,_x2IannotatedTree)
                  {-# LINE 4610 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IoriginalTree,_x2IoriginalTree)
                  {-# LINE 4615 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4620 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4625 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4630 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4635 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4640 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4645 "AstInternal.hs" #-}
              ( _x1IannotatedTree,_x1IoriginalTree,_x1ItypeList) =
                  (x1_ _x1Oenv _x1Olib )
              ( _x2IannotatedTree,_x2IoriginalTree,_x2IproducedEnv,_x2IproducedLib) =
                  (x2_ _x2Oenv _x2OenvUpdates _x2Olib _x2OlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ExpressionListStatementListPairList -------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : ExpressionListStatementListPair 
         child tl             : ExpressionListStatementListPairList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionListStatementListPairList  = [(ExpressionListStatementListPair)]
-- cata
sem_ExpressionListStatementListPairList :: ExpressionListStatementListPairList  ->
                                           T_ExpressionListStatementListPairList 
sem_ExpressionListStatementListPairList list  =
    (Prelude.foldr sem_ExpressionListStatementListPairList_Cons sem_ExpressionListStatementListPairList_Nil (Prelude.map sem_ExpressionListStatementListPair list) )
-- semantic domain
type T_ExpressionListStatementListPairList  = Environment ->
                                              LocalIdentifierBindings ->
                                              ( ExpressionListStatementListPairList,ExpressionListStatementListPairList)
data Inh_ExpressionListStatementListPairList  = Inh_ExpressionListStatementListPairList {env_Inh_ExpressionListStatementListPairList :: Environment,lib_Inh_ExpressionListStatementListPairList :: LocalIdentifierBindings}
data Syn_ExpressionListStatementListPairList  = Syn_ExpressionListStatementListPairList {annotatedTree_Syn_ExpressionListStatementListPairList :: ExpressionListStatementListPairList,originalTree_Syn_ExpressionListStatementListPairList :: ExpressionListStatementListPairList}
wrap_ExpressionListStatementListPairList :: T_ExpressionListStatementListPairList  ->
                                            Inh_ExpressionListStatementListPairList  ->
                                            Syn_ExpressionListStatementListPairList 
wrap_ExpressionListStatementListPairList sem (Inh_ExpressionListStatementListPairList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionListStatementListPairList _lhsOannotatedTree _lhsOoriginalTree ))
sem_ExpressionListStatementListPairList_Cons :: T_ExpressionListStatementListPair  ->
                                                T_ExpressionListStatementListPairList  ->
                                                T_ExpressionListStatementListPairList 
sem_ExpressionListStatementListPairList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionListStatementListPairList
              _lhsOoriginalTree :: ExpressionListStatementListPairList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: ExpressionListStatementListPair
              _hdIoriginalTree :: ExpressionListStatementListPair
              _tlIannotatedTree :: ExpressionListStatementListPairList
              _tlIoriginalTree :: ExpressionListStatementListPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 4711 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 4716 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4721 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4726 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4731 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4736 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4741 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4746 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_ExpressionListStatementListPairList_Nil :: T_ExpressionListStatementListPairList 
sem_ExpressionListStatementListPairList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionListStatementListPairList
              _lhsOoriginalTree :: ExpressionListStatementListPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4762 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 4767 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4772 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4777 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ExpressionRoot ----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative ExpressionRoot:
         child expr           : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data ExpressionRoot  = ExpressionRoot (Expression) 
                     deriving ( Show)
-- cata
sem_ExpressionRoot :: ExpressionRoot  ->
                      T_ExpressionRoot 
sem_ExpressionRoot (ExpressionRoot _expr )  =
    (sem_ExpressionRoot_ExpressionRoot (sem_Expression _expr ) )
-- semantic domain
type T_ExpressionRoot  = Environment ->
                         LocalIdentifierBindings ->
                         ( ExpressionRoot,ExpressionRoot)
data Inh_ExpressionRoot  = Inh_ExpressionRoot {env_Inh_ExpressionRoot :: Environment,lib_Inh_ExpressionRoot :: LocalIdentifierBindings}
data Syn_ExpressionRoot  = Syn_ExpressionRoot {annotatedTree_Syn_ExpressionRoot :: ExpressionRoot,originalTree_Syn_ExpressionRoot :: ExpressionRoot}
wrap_ExpressionRoot :: T_ExpressionRoot  ->
                       Inh_ExpressionRoot  ->
                       Syn_ExpressionRoot 
wrap_ExpressionRoot sem (Inh_ExpressionRoot _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionRoot _lhsOannotatedTree _lhsOoriginalTree ))
sem_ExpressionRoot_ExpressionRoot :: T_Expression  ->
                                     T_ExpressionRoot 
sem_ExpressionRoot_ExpressionRoot expr_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionRoot
              _lhsOoriginalTree :: ExpressionRoot
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ExpressionRoot _exprIannotatedTree
                  {-# LINE 4831 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ExpressionRoot _exprIoriginalTree
                  {-# LINE 4836 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4841 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4846 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4851 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4856 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ExpressionStatementListPair ---------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Tuple:
         child x1             : Expression 
         child x2             : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionStatementListPair  = ( (Expression),(StatementList))
-- cata
sem_ExpressionStatementListPair :: ExpressionStatementListPair  ->
                                   T_ExpressionStatementListPair 
sem_ExpressionStatementListPair ( x1,x2)  =
    (sem_ExpressionStatementListPair_Tuple (sem_Expression x1 ) (sem_StatementList x2 ) )
-- semantic domain
type T_ExpressionStatementListPair  = Environment ->
                                      LocalIdentifierBindings ->
                                      ( ExpressionStatementListPair,ExpressionStatementListPair)
data Inh_ExpressionStatementListPair  = Inh_ExpressionStatementListPair {env_Inh_ExpressionStatementListPair :: Environment,lib_Inh_ExpressionStatementListPair :: LocalIdentifierBindings}
data Syn_ExpressionStatementListPair  = Syn_ExpressionStatementListPair {annotatedTree_Syn_ExpressionStatementListPair :: ExpressionStatementListPair,originalTree_Syn_ExpressionStatementListPair :: ExpressionStatementListPair}
wrap_ExpressionStatementListPair :: T_ExpressionStatementListPair  ->
                                    Inh_ExpressionStatementListPair  ->
                                    Syn_ExpressionStatementListPair 
wrap_ExpressionStatementListPair sem (Inh_ExpressionStatementListPair _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionStatementListPair _lhsOannotatedTree _lhsOoriginalTree ))
sem_ExpressionStatementListPair_Tuple :: T_Expression  ->
                                         T_StatementList  ->
                                         T_ExpressionStatementListPair 
sem_ExpressionStatementListPair_Tuple x1_ x2_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _x2OenvUpdates :: ([EnvironmentUpdate])
              _x2OlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: ExpressionStatementListPair
              _lhsOoriginalTree :: ExpressionStatementListPair
              _x1Oenv :: Environment
              _x1Olib :: LocalIdentifierBindings
              _x2Oenv :: Environment
              _x2Olib :: LocalIdentifierBindings
              _x1IannotatedTree :: Expression
              _x1IliftedColumnName :: String
              _x1IoriginalTree :: Expression
              _x2IannotatedTree :: StatementList
              _x2IoriginalTree :: StatementList
              _x2IproducedEnv :: Environment
              _x2IproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 98, column 9)
              _x2OenvUpdates =
                  {-# LINE 98 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 4921 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 99, column 9)
              _x2OlibUpdates =
                  {-# LINE 99 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 4926 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IannotatedTree,_x2IannotatedTree)
                  {-# LINE 4931 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (_x1IoriginalTree,_x2IoriginalTree)
                  {-# LINE 4936 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 4941 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 4946 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4951 "AstInternal.hs" #-}
              -- copy rule (down)
              _x1Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4956 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 4961 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 4966 "AstInternal.hs" #-}
              ( _x1IannotatedTree,_x1IliftedColumnName,_x1IoriginalTree) =
                  (x1_ _x1Oenv _x1Olib )
              ( _x2IannotatedTree,_x2IoriginalTree,_x2IproducedEnv,_x2IproducedLib) =
                  (x2_ _x2Oenv _x2OenvUpdates _x2Olib _x2OlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ExpressionStatementListPairList -----------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : ExpressionStatementListPair 
         child tl             : ExpressionStatementListPairList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ExpressionStatementListPairList  = [(ExpressionStatementListPair)]
-- cata
sem_ExpressionStatementListPairList :: ExpressionStatementListPairList  ->
                                       T_ExpressionStatementListPairList 
sem_ExpressionStatementListPairList list  =
    (Prelude.foldr sem_ExpressionStatementListPairList_Cons sem_ExpressionStatementListPairList_Nil (Prelude.map sem_ExpressionStatementListPair list) )
-- semantic domain
type T_ExpressionStatementListPairList  = Environment ->
                                          LocalIdentifierBindings ->
                                          ( ExpressionStatementListPairList,ExpressionStatementListPairList)
data Inh_ExpressionStatementListPairList  = Inh_ExpressionStatementListPairList {env_Inh_ExpressionStatementListPairList :: Environment,lib_Inh_ExpressionStatementListPairList :: LocalIdentifierBindings}
data Syn_ExpressionStatementListPairList  = Syn_ExpressionStatementListPairList {annotatedTree_Syn_ExpressionStatementListPairList :: ExpressionStatementListPairList,originalTree_Syn_ExpressionStatementListPairList :: ExpressionStatementListPairList}
wrap_ExpressionStatementListPairList :: T_ExpressionStatementListPairList  ->
                                        Inh_ExpressionStatementListPairList  ->
                                        Syn_ExpressionStatementListPairList 
wrap_ExpressionStatementListPairList sem (Inh_ExpressionStatementListPairList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ExpressionStatementListPairList _lhsOannotatedTree _lhsOoriginalTree ))
sem_ExpressionStatementListPairList_Cons :: T_ExpressionStatementListPair  ->
                                            T_ExpressionStatementListPairList  ->
                                            T_ExpressionStatementListPairList 
sem_ExpressionStatementListPairList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionStatementListPairList
              _lhsOoriginalTree :: ExpressionStatementListPairList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: ExpressionStatementListPair
              _hdIoriginalTree :: ExpressionStatementListPair
              _tlIannotatedTree :: ExpressionStatementListPairList
              _tlIoriginalTree :: ExpressionStatementListPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 5032 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 5037 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5042 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5047 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5052 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5057 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5062 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5067 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_ExpressionStatementListPairList_Nil :: T_ExpressionStatementListPairList 
sem_ExpressionStatementListPairList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: ExpressionStatementListPairList
              _lhsOoriginalTree :: ExpressionStatementListPairList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 5083 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 5088 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5093 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5098 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- FnBody ------------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative PlpgsqlFnBody:
         child ann            : {Annotation}
         child vars           : VarDefList 
         child sts            : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative SqlFnBody:
         child ann            : {Annotation}
         child sts            : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data FnBody  = PlpgsqlFnBody (Annotation) (VarDefList) (StatementList) 
             | SqlFnBody (Annotation) (StatementList) 
             deriving ( Data,Eq,Show,Typeable)
-- cata
sem_FnBody :: FnBody  ->
              T_FnBody 
sem_FnBody (PlpgsqlFnBody _ann _vars _sts )  =
    (sem_FnBody_PlpgsqlFnBody _ann (sem_VarDefList _vars ) (sem_StatementList _sts ) )
sem_FnBody (SqlFnBody _ann _sts )  =
    (sem_FnBody_SqlFnBody _ann (sem_StatementList _sts ) )
-- semantic domain
type T_FnBody  = Environment ->
                 LocalIdentifierBindings ->
                 ( FnBody,FnBody)
data Inh_FnBody  = Inh_FnBody {env_Inh_FnBody :: Environment,lib_Inh_FnBody :: LocalIdentifierBindings}
data Syn_FnBody  = Syn_FnBody {annotatedTree_Syn_FnBody :: FnBody,originalTree_Syn_FnBody :: FnBody}
wrap_FnBody :: T_FnBody  ->
               Inh_FnBody  ->
               Syn_FnBody 
wrap_FnBody sem (Inh_FnBody _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_FnBody _lhsOannotatedTree _lhsOoriginalTree ))
sem_FnBody_PlpgsqlFnBody :: Annotation ->
                            T_VarDefList  ->
                            T_StatementList  ->
                            T_FnBody 
sem_FnBody_PlpgsqlFnBody ann_ vars_ sts_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _stsOenvUpdates :: ([EnvironmentUpdate])
              _stsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _stsOlib :: LocalIdentifierBindings
              _lhsOannotatedTree :: FnBody
              _lhsOoriginalTree :: FnBody
              _varsOenv :: Environment
              _varsOlib :: LocalIdentifierBindings
              _stsOenv :: Environment
              _varsIannotatedTree :: VarDefList
              _varsIdefs :: ([(String,Type)])
              _varsIoriginalTree :: VarDefList
              _stsIannotatedTree :: StatementList
              _stsIoriginalTree :: StatementList
              _stsIproducedEnv :: Environment
              _stsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 102, column 9)
              _stsOenvUpdates =
                  {-# LINE 102 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 5173 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 103, column 9)
              _stsOlibUpdates =
                  {-# LINE 103 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 5178 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 121, column 9)
              _stsOlib =
                  {-# LINE 121 "./TypeChecking/CreateFunction.ag" #-}
                  fromRight _lhsIlib $
                  updateBindings _lhsIlib _lhsIenv
                                 [LibStackIDs [("", _varsIdefs)]]
                  {-# LINE 5185 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  PlpgsqlFnBody ann_ _varsIannotatedTree _stsIannotatedTree
                  {-# LINE 5190 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  PlpgsqlFnBody ann_ _varsIoriginalTree _stsIoriginalTree
                  {-# LINE 5195 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5200 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5205 "AstInternal.hs" #-}
              -- copy rule (down)
              _varsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5210 "AstInternal.hs" #-}
              -- copy rule (down)
              _varsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5215 "AstInternal.hs" #-}
              -- copy rule (down)
              _stsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5220 "AstInternal.hs" #-}
              ( _varsIannotatedTree,_varsIdefs,_varsIoriginalTree) =
                  (vars_ _varsOenv _varsOlib )
              ( _stsIannotatedTree,_stsIoriginalTree,_stsIproducedEnv,_stsIproducedLib) =
                  (sts_ _stsOenv _stsOenvUpdates _stsOlib _stsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_FnBody_SqlFnBody :: Annotation ->
                        T_StatementList  ->
                        T_FnBody 
sem_FnBody_SqlFnBody ann_ sts_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _stsOenvUpdates :: ([EnvironmentUpdate])
              _stsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: FnBody
              _lhsOoriginalTree :: FnBody
              _stsOenv :: Environment
              _stsOlib :: LocalIdentifierBindings
              _stsIannotatedTree :: StatementList
              _stsIoriginalTree :: StatementList
              _stsIproducedEnv :: Environment
              _stsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 102, column 9)
              _stsOenvUpdates =
                  {-# LINE 102 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 5246 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 103, column 9)
              _stsOlibUpdates =
                  {-# LINE 103 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 5251 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SqlFnBody ann_ _stsIannotatedTree
                  {-# LINE 5256 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SqlFnBody ann_ _stsIoriginalTree
                  {-# LINE 5261 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5266 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5271 "AstInternal.hs" #-}
              -- copy rule (down)
              _stsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5276 "AstInternal.hs" #-}
              -- copy rule (down)
              _stsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5281 "AstInternal.hs" #-}
              ( _stsIannotatedTree,_stsIoriginalTree,_stsIproducedEnv,_stsIproducedLib) =
                  (sts_ _stsOenv _stsOenvUpdates _stsOlib _stsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- FrameClause -------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative FrameRowsUnboundedPreceding:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative FrameUnboundedFull:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative FrameUnboundedPreceding:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data FrameClause  = FrameRowsUnboundedPreceding 
                  | FrameUnboundedFull 
                  | FrameUnboundedPreceding 
                  deriving ( Data,Eq,Show,Typeable)
-- cata
sem_FrameClause :: FrameClause  ->
                   T_FrameClause 
sem_FrameClause (FrameRowsUnboundedPreceding )  =
    (sem_FrameClause_FrameRowsUnboundedPreceding )
sem_FrameClause (FrameUnboundedFull )  =
    (sem_FrameClause_FrameUnboundedFull )
sem_FrameClause (FrameUnboundedPreceding )  =
    (sem_FrameClause_FrameUnboundedPreceding )
-- semantic domain
type T_FrameClause  = Environment ->
                      LocalIdentifierBindings ->
                      ( FrameClause,FrameClause)
data Inh_FrameClause  = Inh_FrameClause {env_Inh_FrameClause :: Environment,lib_Inh_FrameClause :: LocalIdentifierBindings}
data Syn_FrameClause  = Syn_FrameClause {annotatedTree_Syn_FrameClause :: FrameClause,originalTree_Syn_FrameClause :: FrameClause}
wrap_FrameClause :: T_FrameClause  ->
                    Inh_FrameClause  ->
                    Syn_FrameClause 
wrap_FrameClause sem (Inh_FrameClause _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_FrameClause _lhsOannotatedTree _lhsOoriginalTree ))
sem_FrameClause_FrameRowsUnboundedPreceding :: T_FrameClause 
sem_FrameClause_FrameRowsUnboundedPreceding  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: FrameClause
              _lhsOoriginalTree :: FrameClause
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  FrameRowsUnboundedPreceding
                  {-# LINE 5344 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  FrameRowsUnboundedPreceding
                  {-# LINE 5349 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5354 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5359 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_FrameClause_FrameUnboundedFull :: T_FrameClause 
sem_FrameClause_FrameUnboundedFull  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: FrameClause
              _lhsOoriginalTree :: FrameClause
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  FrameUnboundedFull
                  {-# LINE 5371 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  FrameUnboundedFull
                  {-# LINE 5376 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5381 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5386 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_FrameClause_FrameUnboundedPreceding :: T_FrameClause 
sem_FrameClause_FrameUnboundedPreceding  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: FrameClause
              _lhsOoriginalTree :: FrameClause
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  FrameUnboundedPreceding
                  {-# LINE 5398 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  FrameUnboundedPreceding
                  {-# LINE 5403 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5408 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5413 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- IfExists ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative IfExists:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Require:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data IfExists  = IfExists 
               | Require 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_IfExists :: IfExists  ->
                T_IfExists 
sem_IfExists (IfExists )  =
    (sem_IfExists_IfExists )
sem_IfExists (Require )  =
    (sem_IfExists_Require )
-- semantic domain
type T_IfExists  = Environment ->
                   LocalIdentifierBindings ->
                   ( IfExists,IfExists)
data Inh_IfExists  = Inh_IfExists {env_Inh_IfExists :: Environment,lib_Inh_IfExists :: LocalIdentifierBindings}
data Syn_IfExists  = Syn_IfExists {annotatedTree_Syn_IfExists :: IfExists,originalTree_Syn_IfExists :: IfExists}
wrap_IfExists :: T_IfExists  ->
                 Inh_IfExists  ->
                 Syn_IfExists 
wrap_IfExists sem (Inh_IfExists _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_IfExists _lhsOannotatedTree _lhsOoriginalTree ))
sem_IfExists_IfExists :: T_IfExists 
sem_IfExists_IfExists  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: IfExists
              _lhsOoriginalTree :: IfExists
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  IfExists
                  {-# LINE 5467 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  IfExists
                  {-# LINE 5472 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5477 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5482 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_IfExists_Require :: T_IfExists 
sem_IfExists_Require  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: IfExists
              _lhsOoriginalTree :: IfExists
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Require
                  {-# LINE 5494 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Require
                  {-# LINE 5499 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5504 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5509 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- InList ------------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         listType             : Either [TypeError] Type
         originalTree         : SELF 
   alternatives:
      alternative InList:
         child ann            : {Annotation}
         child exprs          : ExpressionList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative InSelect:
         child ann            : {Annotation}
         child sel            : SelectExpression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data InList  = InList (Annotation) (ExpressionList) 
             | InSelect (Annotation) (SelectExpression) 
             deriving ( Data,Eq,Show,Typeable)
-- cata
sem_InList :: InList  ->
              T_InList 
sem_InList (InList _ann _exprs )  =
    (sem_InList_InList _ann (sem_ExpressionList _exprs ) )
sem_InList (InSelect _ann _sel )  =
    (sem_InList_InSelect _ann (sem_SelectExpression _sel ) )
-- semantic domain
type T_InList  = Environment ->
                 LocalIdentifierBindings ->
                 ( InList,(Either [TypeError] Type),InList)
data Inh_InList  = Inh_InList {env_Inh_InList :: Environment,lib_Inh_InList :: LocalIdentifierBindings}
data Syn_InList  = Syn_InList {annotatedTree_Syn_InList :: InList,listType_Syn_InList :: Either [TypeError] Type,originalTree_Syn_InList :: InList}
wrap_InList :: T_InList  ->
               Inh_InList  ->
               Syn_InList 
wrap_InList sem (Inh_InList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_InList _lhsOannotatedTree _lhsOlistType _lhsOoriginalTree ))
sem_InList_InList :: Annotation ->
                     T_ExpressionList  ->
                     T_InList 
sem_InList_InList ann_ exprs_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlistType :: (Either [TypeError] Type)
              _lhsOannotatedTree :: InList
              _lhsOoriginalTree :: InList
              _exprsOenv :: Environment
              _exprsOlib :: LocalIdentifierBindings
              _exprsIannotatedTree :: ExpressionList
              _exprsIoriginalTree :: ExpressionList
              _exprsItypeList :: ([Type])
              -- "./TypeChecking/Expressions.ag"(line 305, column 9)
              _lhsOlistType =
                  {-# LINE 305 "./TypeChecking/Expressions.ag" #-}
                  resolveResultSetType _lhsIenv _exprsItypeList
                  {-# LINE 5576 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  InList ann_ _exprsIannotatedTree
                  {-# LINE 5581 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  InList ann_ _exprsIoriginalTree
                  {-# LINE 5586 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5591 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5596 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5601 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5606 "AstInternal.hs" #-}
              ( _exprsIannotatedTree,_exprsIoriginalTree,_exprsItypeList) =
                  (exprs_ _exprsOenv _exprsOlib )
          in  ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree)))
sem_InList_InSelect :: Annotation ->
                       T_SelectExpression  ->
                       T_InList 
sem_InList_InSelect ann_ sel_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlistType :: (Either [TypeError] Type)
              _lhsOannotatedTree :: InList
              _lhsOoriginalTree :: InList
              _selOenv :: Environment
              _selOlib :: LocalIdentifierBindings
              _selIannotatedTree :: SelectExpression
              _selIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selIoriginalTree :: SelectExpression
              -- "./TypeChecking/Expressions.ag"(line 307, column 9)
              _lhsOlistType =
                  {-# LINE 307 "./TypeChecking/Expressions.ag" #-}
                  do
                  attrs <- map snd <$> (unwrapSetOfComposite $
                                        getTypeAnnotation _selIannotatedTree)
                  typ <- case length attrs of
                            0 -> Left [InternalError
                                       "got subquery with no columns? in inselect"]
                            1 -> Right $ head attrs
                            _ -> Right $ AnonymousRecordType attrs
                  dependsOnRTpe attrs $ Right typ
                  {-# LINE 5636 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  InSelect ann_ _selIannotatedTree
                  {-# LINE 5641 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  InSelect ann_ _selIoriginalTree
                  {-# LINE 5646 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5651 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5656 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5661 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5666 "AstInternal.hs" #-}
              ( _selIannotatedTree,_selIlibUpdates,_selIoriginalTree) =
                  (sel_ _selOenv _selOlib )
          in  ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree)))
-- JoinExpression ----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative JoinOn:
         child ann            : {Annotation}
         child expression     : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative JoinUsing:
         child ann            : {Annotation}
         child stringList     : StringList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data JoinExpression  = JoinOn (Annotation) (Expression) 
                     | JoinUsing (Annotation) (StringList) 
                     deriving ( Data,Eq,Show,Typeable)
-- cata
sem_JoinExpression :: JoinExpression  ->
                      T_JoinExpression 
sem_JoinExpression (JoinOn _ann _expression )  =
    (sem_JoinExpression_JoinOn _ann (sem_Expression _expression ) )
sem_JoinExpression (JoinUsing _ann _stringList )  =
    (sem_JoinExpression_JoinUsing _ann (sem_StringList _stringList ) )
-- semantic domain
type T_JoinExpression  = Environment ->
                         LocalIdentifierBindings ->
                         ( JoinExpression,JoinExpression)
data Inh_JoinExpression  = Inh_JoinExpression {env_Inh_JoinExpression :: Environment,lib_Inh_JoinExpression :: LocalIdentifierBindings}
data Syn_JoinExpression  = Syn_JoinExpression {annotatedTree_Syn_JoinExpression :: JoinExpression,originalTree_Syn_JoinExpression :: JoinExpression}
wrap_JoinExpression :: T_JoinExpression  ->
                       Inh_JoinExpression  ->
                       Syn_JoinExpression 
wrap_JoinExpression sem (Inh_JoinExpression _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_JoinExpression _lhsOannotatedTree _lhsOoriginalTree ))
sem_JoinExpression_JoinOn :: Annotation ->
                             T_Expression  ->
                             T_JoinExpression 
sem_JoinExpression_JoinOn ann_ expression_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: JoinExpression
              _lhsOoriginalTree :: JoinExpression
              _expressionOenv :: Environment
              _expressionOlib :: LocalIdentifierBindings
              _expressionIannotatedTree :: Expression
              _expressionIliftedColumnName :: String
              _expressionIoriginalTree :: Expression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  JoinOn ann_ _expressionIannotatedTree
                  {-# LINE 5733 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  JoinOn ann_ _expressionIoriginalTree
                  {-# LINE 5738 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5743 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5748 "AstInternal.hs" #-}
              -- copy rule (down)
              _expressionOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5753 "AstInternal.hs" #-}
              -- copy rule (down)
              _expressionOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5758 "AstInternal.hs" #-}
              ( _expressionIannotatedTree,_expressionIliftedColumnName,_expressionIoriginalTree) =
                  (expression_ _expressionOenv _expressionOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_JoinExpression_JoinUsing :: Annotation ->
                                T_StringList  ->
                                T_JoinExpression 
sem_JoinExpression_JoinUsing ann_ stringList_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: JoinExpression
              _lhsOoriginalTree :: JoinExpression
              _stringListOenv :: Environment
              _stringListOlib :: LocalIdentifierBindings
              _stringListIannotatedTree :: StringList
              _stringListIoriginalTree :: StringList
              _stringListIstrings :: ([String])
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  JoinUsing ann_ _stringListIannotatedTree
                  {-# LINE 5779 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  JoinUsing ann_ _stringListIoriginalTree
                  {-# LINE 5784 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5789 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5794 "AstInternal.hs" #-}
              -- copy rule (down)
              _stringListOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 5799 "AstInternal.hs" #-}
              -- copy rule (down)
              _stringListOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 5804 "AstInternal.hs" #-}
              ( _stringListIannotatedTree,_stringListIoriginalTree,_stringListIstrings) =
                  (stringList_ _stringListOenv _stringListOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- JoinType ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cross:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative FullOuter:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Inner:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative LeftOuter:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RightOuter:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data JoinType  = Cross 
               | FullOuter 
               | Inner 
               | LeftOuter 
               | RightOuter 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_JoinType :: JoinType  ->
                T_JoinType 
sem_JoinType (Cross )  =
    (sem_JoinType_Cross )
sem_JoinType (FullOuter )  =
    (sem_JoinType_FullOuter )
sem_JoinType (Inner )  =
    (sem_JoinType_Inner )
sem_JoinType (LeftOuter )  =
    (sem_JoinType_LeftOuter )
sem_JoinType (RightOuter )  =
    (sem_JoinType_RightOuter )
-- semantic domain
type T_JoinType  = Environment ->
                   LocalIdentifierBindings ->
                   ( JoinType,JoinType)
data Inh_JoinType  = Inh_JoinType {env_Inh_JoinType :: Environment,lib_Inh_JoinType :: LocalIdentifierBindings}
data Syn_JoinType  = Syn_JoinType {annotatedTree_Syn_JoinType :: JoinType,originalTree_Syn_JoinType :: JoinType}
wrap_JoinType :: T_JoinType  ->
                 Inh_JoinType  ->
                 Syn_JoinType 
wrap_JoinType sem (Inh_JoinType _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_JoinType _lhsOannotatedTree _lhsOoriginalTree ))
sem_JoinType_Cross :: T_JoinType 
sem_JoinType_Cross  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: JoinType
              _lhsOoriginalTree :: JoinType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Cross
                  {-# LINE 5881 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Cross
                  {-# LINE 5886 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5891 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5896 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_JoinType_FullOuter :: T_JoinType 
sem_JoinType_FullOuter  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: JoinType
              _lhsOoriginalTree :: JoinType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  FullOuter
                  {-# LINE 5908 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  FullOuter
                  {-# LINE 5913 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5918 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5923 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_JoinType_Inner :: T_JoinType 
sem_JoinType_Inner  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: JoinType
              _lhsOoriginalTree :: JoinType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Inner
                  {-# LINE 5935 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Inner
                  {-# LINE 5940 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5945 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5950 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_JoinType_LeftOuter :: T_JoinType 
sem_JoinType_LeftOuter  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: JoinType
              _lhsOoriginalTree :: JoinType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  LeftOuter
                  {-# LINE 5962 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  LeftOuter
                  {-# LINE 5967 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5972 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 5977 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_JoinType_RightOuter :: T_JoinType 
sem_JoinType_RightOuter  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: JoinType
              _lhsOoriginalTree :: JoinType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RightOuter
                  {-# LINE 5989 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RightOuter
                  {-# LINE 5994 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 5999 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6004 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- Language ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Plpgsql:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Sql:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Language  = Plpgsql 
               | Sql 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Language :: Language  ->
                T_Language 
sem_Language (Plpgsql )  =
    (sem_Language_Plpgsql )
sem_Language (Sql )  =
    (sem_Language_Sql )
-- semantic domain
type T_Language  = Environment ->
                   LocalIdentifierBindings ->
                   ( Language,Language)
data Inh_Language  = Inh_Language {env_Inh_Language :: Environment,lib_Inh_Language :: LocalIdentifierBindings}
data Syn_Language  = Syn_Language {annotatedTree_Syn_Language :: Language,originalTree_Syn_Language :: Language}
wrap_Language :: T_Language  ->
                 Inh_Language  ->
                 Syn_Language 
wrap_Language sem (Inh_Language _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Language _lhsOannotatedTree _lhsOoriginalTree ))
sem_Language_Plpgsql :: T_Language 
sem_Language_Plpgsql  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Language
              _lhsOoriginalTree :: Language
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Plpgsql
                  {-# LINE 6058 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Plpgsql
                  {-# LINE 6063 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6068 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6073 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Language_Sql :: T_Language 
sem_Language_Sql  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Language
              _lhsOoriginalTree :: Language
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Sql
                  {-# LINE 6085 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Sql
                  {-# LINE 6090 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6095 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6100 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- LiftFlavour -------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative LiftAll:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative LiftAny:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data LiftFlavour  = LiftAll 
                  | LiftAny 
                  deriving ( Data,Eq,Show,Typeable)
-- cata
sem_LiftFlavour :: LiftFlavour  ->
                   T_LiftFlavour 
sem_LiftFlavour (LiftAll )  =
    (sem_LiftFlavour_LiftAll )
sem_LiftFlavour (LiftAny )  =
    (sem_LiftFlavour_LiftAny )
-- semantic domain
type T_LiftFlavour  = Environment ->
                      LocalIdentifierBindings ->
                      ( LiftFlavour,LiftFlavour)
data Inh_LiftFlavour  = Inh_LiftFlavour {env_Inh_LiftFlavour :: Environment,lib_Inh_LiftFlavour :: LocalIdentifierBindings}
data Syn_LiftFlavour  = Syn_LiftFlavour {annotatedTree_Syn_LiftFlavour :: LiftFlavour,originalTree_Syn_LiftFlavour :: LiftFlavour}
wrap_LiftFlavour :: T_LiftFlavour  ->
                    Inh_LiftFlavour  ->
                    Syn_LiftFlavour 
wrap_LiftFlavour sem (Inh_LiftFlavour _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_LiftFlavour _lhsOannotatedTree _lhsOoriginalTree ))
sem_LiftFlavour_LiftAll :: T_LiftFlavour 
sem_LiftFlavour_LiftAll  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: LiftFlavour
              _lhsOoriginalTree :: LiftFlavour
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  LiftAll
                  {-# LINE 6154 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  LiftAll
                  {-# LINE 6159 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6164 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6169 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_LiftFlavour_LiftAny :: T_LiftFlavour 
sem_LiftFlavour_LiftAny  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: LiftFlavour
              _lhsOoriginalTree :: LiftFlavour
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  LiftAny
                  {-# LINE 6181 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  LiftAny
                  {-# LINE 6186 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6191 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6196 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- MaybeBoolExpression -----------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Just:
         child just           : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nothing:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type MaybeBoolExpression  = (Maybe (Expression))
-- cata
sem_MaybeBoolExpression :: MaybeBoolExpression  ->
                           T_MaybeBoolExpression 
sem_MaybeBoolExpression (Prelude.Just x )  =
    (sem_MaybeBoolExpression_Just (sem_Expression x ) )
sem_MaybeBoolExpression Prelude.Nothing  =
    sem_MaybeBoolExpression_Nothing
-- semantic domain
type T_MaybeBoolExpression  = Environment ->
                              LocalIdentifierBindings ->
                              ( MaybeBoolExpression,MaybeBoolExpression)
data Inh_MaybeBoolExpression  = Inh_MaybeBoolExpression {env_Inh_MaybeBoolExpression :: Environment,lib_Inh_MaybeBoolExpression :: LocalIdentifierBindings}
data Syn_MaybeBoolExpression  = Syn_MaybeBoolExpression {annotatedTree_Syn_MaybeBoolExpression :: MaybeBoolExpression,originalTree_Syn_MaybeBoolExpression :: MaybeBoolExpression}
wrap_MaybeBoolExpression :: T_MaybeBoolExpression  ->
                            Inh_MaybeBoolExpression  ->
                            Syn_MaybeBoolExpression 
wrap_MaybeBoolExpression sem (Inh_MaybeBoolExpression _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_MaybeBoolExpression _lhsOannotatedTree _lhsOoriginalTree ))
sem_MaybeBoolExpression_Just :: T_Expression  ->
                                T_MaybeBoolExpression 
sem_MaybeBoolExpression_Just just_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: MaybeBoolExpression
              _lhsOoriginalTree :: MaybeBoolExpression
              _justOenv :: Environment
              _justOlib :: LocalIdentifierBindings
              _justIannotatedTree :: Expression
              _justIliftedColumnName :: String
              _justIoriginalTree :: Expression
              -- "./TypeChecking/Misc.ag"(line 74, column 9)
              _lhsOannotatedTree =
                  {-# LINE 74 "./TypeChecking/Misc.ag" #-}
                  if getTypeAnnotation _justIannotatedTree `notElem` [typeBool, TypeCheckFailed]
                    then Just $ updateAnnotation ((TypeErrorA ExpressionMustBeBool) :)
                                  _justIannotatedTree
                    else Just $ _justIannotatedTree
                  {-# LINE 6258 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIannotatedTree
                  {-# LINE 6263 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIoriginalTree
                  {-# LINE 6268 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6273 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 6278 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 6283 "AstInternal.hs" #-}
              ( _justIannotatedTree,_justIliftedColumnName,_justIoriginalTree) =
                  (just_ _justOenv _justOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_MaybeBoolExpression_Nothing :: T_MaybeBoolExpression 
sem_MaybeBoolExpression_Nothing  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: MaybeBoolExpression
              _lhsOoriginalTree :: MaybeBoolExpression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6297 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6302 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6307 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6312 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- MaybeExpression ---------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Just:
         child just           : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nothing:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type MaybeExpression  = (Maybe (Expression))
-- cata
sem_MaybeExpression :: MaybeExpression  ->
                       T_MaybeExpression 
sem_MaybeExpression (Prelude.Just x )  =
    (sem_MaybeExpression_Just (sem_Expression x ) )
sem_MaybeExpression Prelude.Nothing  =
    sem_MaybeExpression_Nothing
-- semantic domain
type T_MaybeExpression  = Environment ->
                          LocalIdentifierBindings ->
                          ( MaybeExpression,MaybeExpression)
data Inh_MaybeExpression  = Inh_MaybeExpression {env_Inh_MaybeExpression :: Environment,lib_Inh_MaybeExpression :: LocalIdentifierBindings}
data Syn_MaybeExpression  = Syn_MaybeExpression {annotatedTree_Syn_MaybeExpression :: MaybeExpression,originalTree_Syn_MaybeExpression :: MaybeExpression}
wrap_MaybeExpression :: T_MaybeExpression  ->
                        Inh_MaybeExpression  ->
                        Syn_MaybeExpression 
wrap_MaybeExpression sem (Inh_MaybeExpression _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_MaybeExpression _lhsOannotatedTree _lhsOoriginalTree ))
sem_MaybeExpression_Just :: T_Expression  ->
                            T_MaybeExpression 
sem_MaybeExpression_Just just_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: MaybeExpression
              _lhsOoriginalTree :: MaybeExpression
              _justOenv :: Environment
              _justOlib :: LocalIdentifierBindings
              _justIannotatedTree :: Expression
              _justIliftedColumnName :: String
              _justIoriginalTree :: Expression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIannotatedTree
                  {-# LINE 6371 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIoriginalTree
                  {-# LINE 6376 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6381 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6386 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 6391 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 6396 "AstInternal.hs" #-}
              ( _justIannotatedTree,_justIliftedColumnName,_justIoriginalTree) =
                  (just_ _justOenv _justOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_MaybeExpression_Nothing :: T_MaybeExpression 
sem_MaybeExpression_Nothing  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: MaybeExpression
              _lhsOoriginalTree :: MaybeExpression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6410 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6415 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6420 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6425 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- MaybeSelectList ---------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         listType             : Maybe [(String,Type)]
         originalTree         : SELF 
   alternatives:
      alternative Just:
         child just           : SelectList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nothing:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type MaybeSelectList  = (Maybe (SelectList))
-- cata
sem_MaybeSelectList :: MaybeSelectList  ->
                       T_MaybeSelectList 
sem_MaybeSelectList (Prelude.Just x )  =
    (sem_MaybeSelectList_Just (sem_SelectList x ) )
sem_MaybeSelectList Prelude.Nothing  =
    sem_MaybeSelectList_Nothing
-- semantic domain
type T_MaybeSelectList  = Environment ->
                          LocalIdentifierBindings ->
                          ( MaybeSelectList,(Maybe [(String,Type)]),MaybeSelectList)
data Inh_MaybeSelectList  = Inh_MaybeSelectList {env_Inh_MaybeSelectList :: Environment,lib_Inh_MaybeSelectList :: LocalIdentifierBindings}
data Syn_MaybeSelectList  = Syn_MaybeSelectList {annotatedTree_Syn_MaybeSelectList :: MaybeSelectList,listType_Syn_MaybeSelectList :: Maybe [(String,Type)],originalTree_Syn_MaybeSelectList :: MaybeSelectList}
wrap_MaybeSelectList :: T_MaybeSelectList  ->
                        Inh_MaybeSelectList  ->
                        Syn_MaybeSelectList 
wrap_MaybeSelectList sem (Inh_MaybeSelectList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_MaybeSelectList _lhsOannotatedTree _lhsOlistType _lhsOoriginalTree ))
sem_MaybeSelectList_Just :: T_SelectList  ->
                            T_MaybeSelectList 
sem_MaybeSelectList_Just just_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlistType :: (Maybe [(String,Type)])
              _lhsOannotatedTree :: MaybeSelectList
              _lhsOoriginalTree :: MaybeSelectList
              _justOenv :: Environment
              _justOlib :: LocalIdentifierBindings
              _justIannotatedTree :: SelectList
              _justIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _justIlistType :: ([(String,Type)])
              _justIoriginalTree :: SelectList
              -- "./TypeChecking/SelectLists.ag"(line 25, column 12)
              _lhsOlistType =
                  {-# LINE 25 "./TypeChecking/SelectLists.ag" #-}
                  Just _justIlistType
                  {-# LINE 6487 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIannotatedTree
                  {-# LINE 6492 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIoriginalTree
                  {-# LINE 6497 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6502 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6507 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 6512 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 6517 "AstInternal.hs" #-}
              ( _justIannotatedTree,_justIlibUpdates,_justIlistType,_justIoriginalTree) =
                  (just_ _justOenv _justOlib )
          in  ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree)))
sem_MaybeSelectList_Nothing :: T_MaybeSelectList 
sem_MaybeSelectList_Nothing  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlistType :: (Maybe [(String,Type)])
              _lhsOannotatedTree :: MaybeSelectList
              _lhsOoriginalTree :: MaybeSelectList
              -- "./TypeChecking/SelectLists.ag"(line 26, column 15)
              _lhsOlistType =
                  {-# LINE 26 "./TypeChecking/SelectLists.ag" #-}
                  Nothing
                  {-# LINE 6532 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6537 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6542 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6547 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6552 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree)))
-- Natural -----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Natural:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Unnatural:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Natural  = Natural 
              | Unnatural 
              deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Natural :: Natural  ->
               T_Natural 
sem_Natural (Natural )  =
    (sem_Natural_Natural )
sem_Natural (Unnatural )  =
    (sem_Natural_Unnatural )
-- semantic domain
type T_Natural  = Environment ->
                  LocalIdentifierBindings ->
                  ( Natural,Natural)
data Inh_Natural  = Inh_Natural {env_Inh_Natural :: Environment,lib_Inh_Natural :: LocalIdentifierBindings}
data Syn_Natural  = Syn_Natural {annotatedTree_Syn_Natural :: Natural,originalTree_Syn_Natural :: Natural}
wrap_Natural :: T_Natural  ->
                Inh_Natural  ->
                Syn_Natural 
wrap_Natural sem (Inh_Natural _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Natural _lhsOannotatedTree _lhsOoriginalTree ))
sem_Natural_Natural :: T_Natural 
sem_Natural_Natural  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Natural
              _lhsOoriginalTree :: Natural
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Natural
                  {-# LINE 6606 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Natural
                  {-# LINE 6611 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6616 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6621 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Natural_Unnatural :: T_Natural 
sem_Natural_Unnatural  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Natural
              _lhsOoriginalTree :: Natural
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Unnatural
                  {-# LINE 6633 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Unnatural
                  {-# LINE 6638 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6643 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6648 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- OnExpr ------------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Just:
         child just           : JoinExpression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nothing:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type OnExpr  = (Maybe (JoinExpression))
-- cata
sem_OnExpr :: OnExpr  ->
              T_OnExpr 
sem_OnExpr (Prelude.Just x )  =
    (sem_OnExpr_Just (sem_JoinExpression x ) )
sem_OnExpr Prelude.Nothing  =
    sem_OnExpr_Nothing
-- semantic domain
type T_OnExpr  = Environment ->
                 LocalIdentifierBindings ->
                 ( OnExpr,OnExpr)
data Inh_OnExpr  = Inh_OnExpr {env_Inh_OnExpr :: Environment,lib_Inh_OnExpr :: LocalIdentifierBindings}
data Syn_OnExpr  = Syn_OnExpr {annotatedTree_Syn_OnExpr :: OnExpr,originalTree_Syn_OnExpr :: OnExpr}
wrap_OnExpr :: T_OnExpr  ->
               Inh_OnExpr  ->
               Syn_OnExpr 
wrap_OnExpr sem (Inh_OnExpr _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_OnExpr _lhsOannotatedTree _lhsOoriginalTree ))
sem_OnExpr_Just :: T_JoinExpression  ->
                   T_OnExpr 
sem_OnExpr_Just just_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: OnExpr
              _lhsOoriginalTree :: OnExpr
              _justOenv :: Environment
              _justOlib :: LocalIdentifierBindings
              _justIannotatedTree :: JoinExpression
              _justIoriginalTree :: JoinExpression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIannotatedTree
                  {-# LINE 6706 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Just _justIoriginalTree
                  {-# LINE 6711 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6716 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6721 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 6726 "AstInternal.hs" #-}
              -- copy rule (down)
              _justOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 6731 "AstInternal.hs" #-}
              ( _justIannotatedTree,_justIoriginalTree) =
                  (just_ _justOenv _justOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_OnExpr_Nothing :: T_OnExpr 
sem_OnExpr_Nothing  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: OnExpr
              _lhsOoriginalTree :: OnExpr
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6745 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Nothing
                  {-# LINE 6750 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6755 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6760 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- ParamDef ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         namedType            : Type
         originalTree         : SELF 
         paramName            : String
   alternatives:
      alternative ParamDef:
         child ann            : {Annotation}
         child name           : {String}
         child typ            : TypeName 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative ParamDefTp:
         child ann            : {Annotation}
         child typ            : TypeName 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data ParamDef  = ParamDef (Annotation) (String) (TypeName) 
               | ParamDefTp (Annotation) (TypeName) 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_ParamDef :: ParamDef  ->
                T_ParamDef 
sem_ParamDef (ParamDef _ann _name _typ )  =
    (sem_ParamDef_ParamDef _ann _name (sem_TypeName _typ ) )
sem_ParamDef (ParamDefTp _ann _typ )  =
    (sem_ParamDef_ParamDefTp _ann (sem_TypeName _typ ) )
-- semantic domain
type T_ParamDef  = Environment ->
                   LocalIdentifierBindings ->
                   ( ParamDef,Type,ParamDef,String)
data Inh_ParamDef  = Inh_ParamDef {env_Inh_ParamDef :: Environment,lib_Inh_ParamDef :: LocalIdentifierBindings}
data Syn_ParamDef  = Syn_ParamDef {annotatedTree_Syn_ParamDef :: ParamDef,namedType_Syn_ParamDef :: Type,originalTree_Syn_ParamDef :: ParamDef,paramName_Syn_ParamDef :: String}
wrap_ParamDef :: T_ParamDef  ->
                 Inh_ParamDef  ->
                 Syn_ParamDef 
wrap_ParamDef sem (Inh_ParamDef _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree,_lhsOparamName) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ParamDef _lhsOannotatedTree _lhsOnamedType _lhsOoriginalTree _lhsOparamName ))
sem_ParamDef_ParamDef :: Annotation ->
                         String ->
                         T_TypeName  ->
                         T_ParamDef 
sem_ParamDef_ParamDef ann_ name_ typ_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedType :: Type
              _lhsOparamName :: String
              _lhsOannotatedTree :: ParamDef
              _lhsOoriginalTree :: ParamDef
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              -- "./TypeChecking/CreateFunction.ag"(line 56, column 9)
              _lhsOnamedType =
                  {-# LINE 56 "./TypeChecking/CreateFunction.ag" #-}
                  _typInamedType
                  {-# LINE 6831 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 58, column 9)
              _lhsOparamName =
                  {-# LINE 58 "./TypeChecking/CreateFunction.ag" #-}
                  name_
                  {-# LINE 6836 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ParamDef ann_ name_ _typIannotatedTree
                  {-# LINE 6841 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ParamDef ann_ name_ _typIoriginalTree
                  {-# LINE 6846 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6851 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6856 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 6861 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 6866 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
          in  ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree,_lhsOparamName)))
sem_ParamDef_ParamDefTp :: Annotation ->
                           T_TypeName  ->
                           T_ParamDef 
sem_ParamDef_ParamDefTp ann_ typ_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedType :: Type
              _lhsOparamName :: String
              _lhsOannotatedTree :: ParamDef
              _lhsOoriginalTree :: ParamDef
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              -- "./TypeChecking/CreateFunction.ag"(line 56, column 9)
              _lhsOnamedType =
                  {-# LINE 56 "./TypeChecking/CreateFunction.ag" #-}
                  _typInamedType
                  {-# LINE 6889 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 60, column 9)
              _lhsOparamName =
                  {-# LINE 60 "./TypeChecking/CreateFunction.ag" #-}
                  ""
                  {-# LINE 6894 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ParamDefTp ann_ _typIannotatedTree
                  {-# LINE 6899 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ParamDefTp ann_ _typIoriginalTree
                  {-# LINE 6904 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 6909 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 6914 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 6919 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 6924 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
          in  ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree,_lhsOparamName)))
-- ParamDefList ------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         params               : [(String, Type)]
   alternatives:
      alternative Cons:
         child hd             : ParamDef 
         child tl             : ParamDefList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type ParamDefList  = [(ParamDef)]
-- cata
sem_ParamDefList :: ParamDefList  ->
                    T_ParamDefList 
sem_ParamDefList list  =
    (Prelude.foldr sem_ParamDefList_Cons sem_ParamDefList_Nil (Prelude.map sem_ParamDef list) )
-- semantic domain
type T_ParamDefList  = Environment ->
                       LocalIdentifierBindings ->
                       ( ParamDefList,ParamDefList,([(String, Type)]))
data Inh_ParamDefList  = Inh_ParamDefList {env_Inh_ParamDefList :: Environment,lib_Inh_ParamDefList :: LocalIdentifierBindings}
data Syn_ParamDefList  = Syn_ParamDefList {annotatedTree_Syn_ParamDefList :: ParamDefList,originalTree_Syn_ParamDefList :: ParamDefList,params_Syn_ParamDefList :: [(String, Type)]}
wrap_ParamDefList :: T_ParamDefList  ->
                     Inh_ParamDefList  ->
                     Syn_ParamDefList 
wrap_ParamDefList sem (Inh_ParamDefList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOparams) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_ParamDefList _lhsOannotatedTree _lhsOoriginalTree _lhsOparams ))
sem_ParamDefList_Cons :: T_ParamDef  ->
                         T_ParamDefList  ->
                         T_ParamDefList 
sem_ParamDefList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOparams :: ([(String, Type)])
              _lhsOannotatedTree :: ParamDefList
              _lhsOoriginalTree :: ParamDefList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: ParamDef
              _hdInamedType :: Type
              _hdIoriginalTree :: ParamDef
              _hdIparamName :: String
              _tlIannotatedTree :: ParamDefList
              _tlIoriginalTree :: ParamDefList
              _tlIparams :: ([(String, Type)])
              -- "./TypeChecking/CreateFunction.ag"(line 64, column 13)
              _lhsOparams =
                  {-# LINE 64 "./TypeChecking/CreateFunction.ag" #-}
                  ((_hdIparamName, _hdInamedType) : _tlIparams)
                  {-# LINE 6993 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 6998 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 7003 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7008 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7013 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7018 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7023 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7028 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7033 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdInamedType,_hdIoriginalTree,_hdIparamName) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree,_tlIparams) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOparams)))
sem_ParamDefList_Nil :: T_ParamDefList 
sem_ParamDefList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOparams :: ([(String, Type)])
              _lhsOannotatedTree :: ParamDefList
              _lhsOoriginalTree :: ParamDefList
              -- "./TypeChecking/CreateFunction.ag"(line 63, column 12)
              _lhsOparams =
                  {-# LINE 63 "./TypeChecking/CreateFunction.ag" #-}
                  []
                  {-# LINE 7050 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 7055 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 7060 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7065 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7070 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOparams)))
-- RaiseType ---------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative RError:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RException:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RNotice:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data RaiseType  = RError 
                | RException 
                | RNotice 
                deriving ( Data,Eq,Show,Typeable)
-- cata
sem_RaiseType :: RaiseType  ->
                 T_RaiseType 
sem_RaiseType (RError )  =
    (sem_RaiseType_RError )
sem_RaiseType (RException )  =
    (sem_RaiseType_RException )
sem_RaiseType (RNotice )  =
    (sem_RaiseType_RNotice )
-- semantic domain
type T_RaiseType  = Environment ->
                    LocalIdentifierBindings ->
                    ( RaiseType,RaiseType)
data Inh_RaiseType  = Inh_RaiseType {env_Inh_RaiseType :: Environment,lib_Inh_RaiseType :: LocalIdentifierBindings}
data Syn_RaiseType  = Syn_RaiseType {annotatedTree_Syn_RaiseType :: RaiseType,originalTree_Syn_RaiseType :: RaiseType}
wrap_RaiseType :: T_RaiseType  ->
                  Inh_RaiseType  ->
                  Syn_RaiseType 
wrap_RaiseType sem (Inh_RaiseType _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_RaiseType _lhsOannotatedTree _lhsOoriginalTree ))
sem_RaiseType_RError :: T_RaiseType 
sem_RaiseType_RError  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RaiseType
              _lhsOoriginalTree :: RaiseType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RError
                  {-# LINE 7131 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RError
                  {-# LINE 7136 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7141 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7146 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RaiseType_RException :: T_RaiseType 
sem_RaiseType_RException  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RaiseType
              _lhsOoriginalTree :: RaiseType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RException
                  {-# LINE 7158 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RException
                  {-# LINE 7163 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7168 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7173 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RaiseType_RNotice :: T_RaiseType 
sem_RaiseType_RNotice  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RaiseType
              _lhsOoriginalTree :: RaiseType
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RNotice
                  {-# LINE 7185 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RNotice
                  {-# LINE 7190 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7195 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7200 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- RestartIdentity ---------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative ContinueIdentity:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RestartIdentity:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data RestartIdentity  = ContinueIdentity 
                      | RestartIdentity 
                      deriving ( Data,Eq,Show,Typeable)
-- cata
sem_RestartIdentity :: RestartIdentity  ->
                       T_RestartIdentity 
sem_RestartIdentity (ContinueIdentity )  =
    (sem_RestartIdentity_ContinueIdentity )
sem_RestartIdentity (RestartIdentity )  =
    (sem_RestartIdentity_RestartIdentity )
-- semantic domain
type T_RestartIdentity  = Environment ->
                          LocalIdentifierBindings ->
                          ( RestartIdentity,RestartIdentity)
data Inh_RestartIdentity  = Inh_RestartIdentity {env_Inh_RestartIdentity :: Environment,lib_Inh_RestartIdentity :: LocalIdentifierBindings}
data Syn_RestartIdentity  = Syn_RestartIdentity {annotatedTree_Syn_RestartIdentity :: RestartIdentity,originalTree_Syn_RestartIdentity :: RestartIdentity}
wrap_RestartIdentity :: T_RestartIdentity  ->
                        Inh_RestartIdentity  ->
                        Syn_RestartIdentity 
wrap_RestartIdentity sem (Inh_RestartIdentity _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_RestartIdentity _lhsOannotatedTree _lhsOoriginalTree ))
sem_RestartIdentity_ContinueIdentity :: T_RestartIdentity 
sem_RestartIdentity_ContinueIdentity  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RestartIdentity
              _lhsOoriginalTree :: RestartIdentity
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ContinueIdentity
                  {-# LINE 7254 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ContinueIdentity
                  {-# LINE 7259 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7264 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7269 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RestartIdentity_RestartIdentity :: T_RestartIdentity 
sem_RestartIdentity_RestartIdentity  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RestartIdentity
              _lhsOoriginalTree :: RestartIdentity
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RestartIdentity
                  {-# LINE 7281 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RestartIdentity
                  {-# LINE 7286 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7291 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7296 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- Root --------------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         producedEnv          : Environment
         producedLib          : LocalIdentifierBindings
   alternatives:
      alternative Root:
         child statements     : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Root  = Root (StatementList) 
           deriving ( Show)
-- cata
sem_Root :: Root  ->
            T_Root 
sem_Root (Root _statements )  =
    (sem_Root_Root (sem_StatementList _statements ) )
-- semantic domain
type T_Root  = Environment ->
               LocalIdentifierBindings ->
               ( Root,Root,Environment,LocalIdentifierBindings)
data Inh_Root  = Inh_Root {env_Inh_Root :: Environment,lib_Inh_Root :: LocalIdentifierBindings}
data Syn_Root  = Syn_Root {annotatedTree_Syn_Root :: Root,originalTree_Syn_Root :: Root,producedEnv_Syn_Root :: Environment,producedLib_Syn_Root :: LocalIdentifierBindings}
wrap_Root :: T_Root  ->
             Inh_Root  ->
             Syn_Root 
wrap_Root sem (Inh_Root _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOproducedEnv,_lhsOproducedLib) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Root _lhsOannotatedTree _lhsOoriginalTree _lhsOproducedEnv _lhsOproducedLib ))
sem_Root_Root :: T_StatementList  ->
                 T_Root 
sem_Root_Root statements_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _statementsOenvUpdates :: ([EnvironmentUpdate])
              _statementsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Root
              _lhsOoriginalTree :: Root
              _lhsOproducedEnv :: Environment
              _lhsOproducedLib :: LocalIdentifierBindings
              _statementsOenv :: Environment
              _statementsOlib :: LocalIdentifierBindings
              _statementsIannotatedTree :: StatementList
              _statementsIoriginalTree :: StatementList
              _statementsIproducedEnv :: Environment
              _statementsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 80, column 12)
              _statementsOenvUpdates =
                  {-# LINE 80 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 7357 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 81, column 12)
              _statementsOlibUpdates =
                  {-# LINE 81 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 7362 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Root _statementsIannotatedTree
                  {-# LINE 7367 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Root _statementsIoriginalTree
                  {-# LINE 7372 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7377 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7382 "AstInternal.hs" #-}
              -- copy rule (up)
              _lhsOproducedEnv =
                  {-# LINE 27 "./TypeChecking/Statements.ag" #-}
                  _statementsIproducedEnv
                  {-# LINE 7387 "AstInternal.hs" #-}
              -- copy rule (up)
              _lhsOproducedLib =
                  {-# LINE 28 "./TypeChecking/Statements.ag" #-}
                  _statementsIproducedLib
                  {-# LINE 7392 "AstInternal.hs" #-}
              -- copy rule (down)
              _statementsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7397 "AstInternal.hs" #-}
              -- copy rule (down)
              _statementsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7402 "AstInternal.hs" #-}
              ( _statementsIannotatedTree,_statementsIoriginalTree,_statementsIproducedEnv,_statementsIproducedLib) =
                  (statements_ _statementsOenv _statementsOenvUpdates _statementsOlib _statementsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOproducedEnv,_lhsOproducedLib)))
-- RowConstraint -----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative NotNullConstraint:
         child ann            : {Annotation}
         child name           : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative NullConstraint:
         child ann            : {Annotation}
         child name           : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RowCheckConstraint:
         child ann            : {Annotation}
         child name           : {String}
         child expression     : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RowPrimaryKeyConstraint:
         child ann            : {Annotation}
         child name           : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RowReferenceConstraint:
         child ann            : {Annotation}
         child name           : {String}
         child table          : {String}
         child att            : {Maybe String}
         child onUpdate       : Cascade 
         child onDelete       : Cascade 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative RowUniqueConstraint:
         child ann            : {Annotation}
         child name           : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data RowConstraint  = NotNullConstraint (Annotation) (String) 
                    | NullConstraint (Annotation) (String) 
                    | RowCheckConstraint (Annotation) (String) (Expression) 
                    | RowPrimaryKeyConstraint (Annotation) (String) 
                    | RowReferenceConstraint (Annotation) (String) (String) (Maybe String) (Cascade) (Cascade) 
                    | RowUniqueConstraint (Annotation) (String) 
                    deriving ( Data,Eq,Show,Typeable)
-- cata
sem_RowConstraint :: RowConstraint  ->
                     T_RowConstraint 
sem_RowConstraint (NotNullConstraint _ann _name )  =
    (sem_RowConstraint_NotNullConstraint _ann _name )
sem_RowConstraint (NullConstraint _ann _name )  =
    (sem_RowConstraint_NullConstraint _ann _name )
sem_RowConstraint (RowCheckConstraint _ann _name _expression )  =
    (sem_RowConstraint_RowCheckConstraint _ann _name (sem_Expression _expression ) )
sem_RowConstraint (RowPrimaryKeyConstraint _ann _name )  =
    (sem_RowConstraint_RowPrimaryKeyConstraint _ann _name )
sem_RowConstraint (RowReferenceConstraint _ann _name _table _att _onUpdate _onDelete )  =
    (sem_RowConstraint_RowReferenceConstraint _ann _name _table _att (sem_Cascade _onUpdate ) (sem_Cascade _onDelete ) )
sem_RowConstraint (RowUniqueConstraint _ann _name )  =
    (sem_RowConstraint_RowUniqueConstraint _ann _name )
-- semantic domain
type T_RowConstraint  = Environment ->
                        LocalIdentifierBindings ->
                        ( RowConstraint,RowConstraint)
data Inh_RowConstraint  = Inh_RowConstraint {env_Inh_RowConstraint :: Environment,lib_Inh_RowConstraint :: LocalIdentifierBindings}
data Syn_RowConstraint  = Syn_RowConstraint {annotatedTree_Syn_RowConstraint :: RowConstraint,originalTree_Syn_RowConstraint :: RowConstraint}
wrap_RowConstraint :: T_RowConstraint  ->
                      Inh_RowConstraint  ->
                      Syn_RowConstraint 
wrap_RowConstraint sem (Inh_RowConstraint _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_RowConstraint _lhsOannotatedTree _lhsOoriginalTree ))
sem_RowConstraint_NotNullConstraint :: Annotation ->
                                       String ->
                                       T_RowConstraint 
sem_RowConstraint_NotNullConstraint ann_ name_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraint
              _lhsOoriginalTree :: RowConstraint
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  NotNullConstraint ann_ name_
                  {-# LINE 7505 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  NotNullConstraint ann_ name_
                  {-# LINE 7510 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7515 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7520 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RowConstraint_NullConstraint :: Annotation ->
                                    String ->
                                    T_RowConstraint 
sem_RowConstraint_NullConstraint ann_ name_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraint
              _lhsOoriginalTree :: RowConstraint
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  NullConstraint ann_ name_
                  {-# LINE 7534 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  NullConstraint ann_ name_
                  {-# LINE 7539 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7544 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7549 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RowConstraint_RowCheckConstraint :: Annotation ->
                                        String ->
                                        T_Expression  ->
                                        T_RowConstraint 
sem_RowConstraint_RowCheckConstraint ann_ name_ expression_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraint
              _lhsOoriginalTree :: RowConstraint
              _expressionOenv :: Environment
              _expressionOlib :: LocalIdentifierBindings
              _expressionIannotatedTree :: Expression
              _expressionIliftedColumnName :: String
              _expressionIoriginalTree :: Expression
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RowCheckConstraint ann_ name_ _expressionIannotatedTree
                  {-# LINE 7569 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RowCheckConstraint ann_ name_ _expressionIoriginalTree
                  {-# LINE 7574 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7579 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7584 "AstInternal.hs" #-}
              -- copy rule (down)
              _expressionOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7589 "AstInternal.hs" #-}
              -- copy rule (down)
              _expressionOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7594 "AstInternal.hs" #-}
              ( _expressionIannotatedTree,_expressionIliftedColumnName,_expressionIoriginalTree) =
                  (expression_ _expressionOenv _expressionOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RowConstraint_RowPrimaryKeyConstraint :: Annotation ->
                                             String ->
                                             T_RowConstraint 
sem_RowConstraint_RowPrimaryKeyConstraint ann_ name_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraint
              _lhsOoriginalTree :: RowConstraint
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RowPrimaryKeyConstraint ann_ name_
                  {-# LINE 7610 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RowPrimaryKeyConstraint ann_ name_
                  {-# LINE 7615 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7620 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7625 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RowConstraint_RowReferenceConstraint :: Annotation ->
                                            String ->
                                            String ->
                                            (Maybe String) ->
                                            T_Cascade  ->
                                            T_Cascade  ->
                                            T_RowConstraint 
sem_RowConstraint_RowReferenceConstraint ann_ name_ table_ att_ onUpdate_ onDelete_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraint
              _lhsOoriginalTree :: RowConstraint
              _onUpdateOenv :: Environment
              _onUpdateOlib :: LocalIdentifierBindings
              _onDeleteOenv :: Environment
              _onDeleteOlib :: LocalIdentifierBindings
              _onUpdateIannotatedTree :: Cascade
              _onUpdateIoriginalTree :: Cascade
              _onDeleteIannotatedTree :: Cascade
              _onDeleteIoriginalTree :: Cascade
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RowReferenceConstraint ann_ name_ table_ att_ _onUpdateIannotatedTree _onDeleteIannotatedTree
                  {-# LINE 7651 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RowReferenceConstraint ann_ name_ table_ att_ _onUpdateIoriginalTree _onDeleteIoriginalTree
                  {-# LINE 7656 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7661 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7666 "AstInternal.hs" #-}
              -- copy rule (down)
              _onUpdateOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7671 "AstInternal.hs" #-}
              -- copy rule (down)
              _onUpdateOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7676 "AstInternal.hs" #-}
              -- copy rule (down)
              _onDeleteOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7681 "AstInternal.hs" #-}
              -- copy rule (down)
              _onDeleteOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7686 "AstInternal.hs" #-}
              ( _onUpdateIannotatedTree,_onUpdateIoriginalTree) =
                  (onUpdate_ _onUpdateOenv _onUpdateOlib )
              ( _onDeleteIannotatedTree,_onDeleteIoriginalTree) =
                  (onDelete_ _onDeleteOenv _onDeleteOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RowConstraint_RowUniqueConstraint :: Annotation ->
                                         String ->
                                         T_RowConstraint 
sem_RowConstraint_RowUniqueConstraint ann_ name_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraint
              _lhsOoriginalTree :: RowConstraint
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RowUniqueConstraint ann_ name_
                  {-# LINE 7704 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RowUniqueConstraint ann_ name_
                  {-# LINE 7709 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7714 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7719 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- RowConstraintList -------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : RowConstraint 
         child tl             : RowConstraintList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type RowConstraintList  = [(RowConstraint)]
-- cata
sem_RowConstraintList :: RowConstraintList  ->
                         T_RowConstraintList 
sem_RowConstraintList list  =
    (Prelude.foldr sem_RowConstraintList_Cons sem_RowConstraintList_Nil (Prelude.map sem_RowConstraint list) )
-- semantic domain
type T_RowConstraintList  = Environment ->
                            LocalIdentifierBindings ->
                            ( RowConstraintList,RowConstraintList)
data Inh_RowConstraintList  = Inh_RowConstraintList {env_Inh_RowConstraintList :: Environment,lib_Inh_RowConstraintList :: LocalIdentifierBindings}
data Syn_RowConstraintList  = Syn_RowConstraintList {annotatedTree_Syn_RowConstraintList :: RowConstraintList,originalTree_Syn_RowConstraintList :: RowConstraintList}
wrap_RowConstraintList :: T_RowConstraintList  ->
                          Inh_RowConstraintList  ->
                          Syn_RowConstraintList 
wrap_RowConstraintList sem (Inh_RowConstraintList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_RowConstraintList _lhsOannotatedTree _lhsOoriginalTree ))
sem_RowConstraintList_Cons :: T_RowConstraint  ->
                              T_RowConstraintList  ->
                              T_RowConstraintList 
sem_RowConstraintList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraintList
              _lhsOoriginalTree :: RowConstraintList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: RowConstraint
              _hdIoriginalTree :: RowConstraint
              _tlIannotatedTree :: RowConstraintList
              _tlIoriginalTree :: RowConstraintList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 7781 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 7786 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7791 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7796 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7801 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7806 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7811 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7816 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_RowConstraintList_Nil :: T_RowConstraintList 
sem_RowConstraintList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: RowConstraintList
              _lhsOoriginalTree :: RowConstraintList
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 7832 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 7837 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 7842 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7847 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- SelectExpression --------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         libUpdates           : [LocalIdentifierBindingsUpdate]
         originalTree         : SELF 
   alternatives:
      alternative CombineSelect:
         child ann            : {Annotation}
         child ctype          : CombineType 
         child sel1           : SelectExpression 
         child sel2           : SelectExpression 
         visit 0:
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Select:
         child ann            : {Annotation}
         child selDistinct    : Distinct 
         child selSelectList  : SelectList 
         child selTref        : TableRefList 
         child selWhere       : MaybeBoolExpression 
         child selGroupBy     : ExpressionList 
         child selHaving      : MaybeBoolExpression 
         child selOrderBy     : ExpressionDirectionPairList 
         child selLimit       : MaybeExpression 
         child selOffset      : MaybeExpression 
         visit 0:
            local newLib      : _
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Values:
         child ann            : {Annotation}
         child vll            : ExpressionListList 
         visit 0:
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
-}
data SelectExpression  = CombineSelect (Annotation) (CombineType) (SelectExpression) (SelectExpression) 
                       | Select (Annotation) (Distinct) (SelectList) (TableRefList) (MaybeBoolExpression) (ExpressionList) (MaybeBoolExpression) (ExpressionDirectionPairList) (MaybeExpression) (MaybeExpression) 
                       | Values (Annotation) (ExpressionListList) 
                       deriving ( Data,Eq,Show,Typeable)
-- cata
sem_SelectExpression :: SelectExpression  ->
                        T_SelectExpression 
sem_SelectExpression (CombineSelect _ann _ctype _sel1 _sel2 )  =
    (sem_SelectExpression_CombineSelect _ann (sem_CombineType _ctype ) (sem_SelectExpression _sel1 ) (sem_SelectExpression _sel2 ) )
sem_SelectExpression (Select _ann _selDistinct _selSelectList _selTref _selWhere _selGroupBy _selHaving _selOrderBy _selLimit _selOffset )  =
    (sem_SelectExpression_Select _ann (sem_Distinct _selDistinct ) (sem_SelectList _selSelectList ) (sem_TableRefList _selTref ) (sem_MaybeBoolExpression _selWhere ) (sem_ExpressionList _selGroupBy ) (sem_MaybeBoolExpression _selHaving ) (sem_ExpressionDirectionPairList _selOrderBy ) (sem_MaybeExpression _selLimit ) (sem_MaybeExpression _selOffset ) )
sem_SelectExpression (Values _ann _vll )  =
    (sem_SelectExpression_Values _ann (sem_ExpressionListList _vll ) )
-- semantic domain
type T_SelectExpression  = Environment ->
                           LocalIdentifierBindings ->
                           ( SelectExpression,([LocalIdentifierBindingsUpdate]),SelectExpression)
data Inh_SelectExpression  = Inh_SelectExpression {env_Inh_SelectExpression :: Environment,lib_Inh_SelectExpression :: LocalIdentifierBindings}
data Syn_SelectExpression  = Syn_SelectExpression {annotatedTree_Syn_SelectExpression :: SelectExpression,libUpdates_Syn_SelectExpression :: [LocalIdentifierBindingsUpdate],originalTree_Syn_SelectExpression :: SelectExpression}
wrap_SelectExpression :: T_SelectExpression  ->
                         Inh_SelectExpression  ->
                         Syn_SelectExpression 
wrap_SelectExpression sem (Inh_SelectExpression _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_SelectExpression _lhsOannotatedTree _lhsOlibUpdates _lhsOoriginalTree ))
sem_SelectExpression_CombineSelect :: Annotation ->
                                      T_CombineType  ->
                                      T_SelectExpression  ->
                                      T_SelectExpression  ->
                                      T_SelectExpression 
sem_SelectExpression_CombineSelect ann_ ctype_ sel1_ sel2_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: SelectExpression
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOoriginalTree :: SelectExpression
              _ctypeOenv :: Environment
              _ctypeOlib :: LocalIdentifierBindings
              _sel1Oenv :: Environment
              _sel1Olib :: LocalIdentifierBindings
              _sel2Oenv :: Environment
              _sel2Olib :: LocalIdentifierBindings
              _ctypeIannotatedTree :: CombineType
              _ctypeIoriginalTree :: CombineType
              _sel1IannotatedTree :: SelectExpression
              _sel1IlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _sel1IoriginalTree :: SelectExpression
              _sel2IannotatedTree :: SelectExpression
              _sel2IlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _sel2IoriginalTree :: SelectExpression
              -- "./TypeChecking/SelectStatement.ag"(line 23, column 9)
              _lhsOannotatedTree =
                  {-# LINE 23 "./TypeChecking/SelectStatement.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    Nothing
                  {-# LINE 7954 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 129, column 9)
              _tpe =
                  {-# LINE 129 "./TypeChecking/SelectStatement.ag" #-}
                  let sel1t = getTypeAnnotation _sel1IannotatedTree
                      sel2t = getTypeAnnotation _sel2IannotatedTree
                  in dependsOnRTpe [sel1t, sel2t] $
                        typeCheckCombineSelect _lhsIenv sel1t sel2t
                  {-# LINE 7962 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 134, column 9)
              _backTree =
                  {-# LINE 134 "./TypeChecking/SelectStatement.ag" #-}
                  CombineSelect ann_ _ctypeIannotatedTree
                                _sel1IannotatedTree
                                _sel2IannotatedTree
                  {-# LINE 7969 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 87, column 11)
              _lhsOlibUpdates =
                  {-# LINE 87 "./TypeChecking/SelectLists.ag" #-}
                  []
                  {-# LINE 7974 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CombineSelect ann_ _ctypeIannotatedTree _sel1IannotatedTree _sel2IannotatedTree
                  {-# LINE 7979 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CombineSelect ann_ _ctypeIoriginalTree _sel1IoriginalTree _sel2IoriginalTree
                  {-# LINE 7984 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 7989 "AstInternal.hs" #-}
              -- copy rule (down)
              _ctypeOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 7994 "AstInternal.hs" #-}
              -- copy rule (down)
              _ctypeOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 7999 "AstInternal.hs" #-}
              -- copy rule (down)
              _sel1Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8004 "AstInternal.hs" #-}
              -- copy rule (down)
              _sel1Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8009 "AstInternal.hs" #-}
              -- copy rule (down)
              _sel2Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8014 "AstInternal.hs" #-}
              -- copy rule (down)
              _sel2Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8019 "AstInternal.hs" #-}
              ( _ctypeIannotatedTree,_ctypeIoriginalTree) =
                  (ctype_ _ctypeOenv _ctypeOlib )
              ( _sel1IannotatedTree,_sel1IlibUpdates,_sel1IoriginalTree) =
                  (sel1_ _sel1Oenv _sel1Olib )
              ( _sel2IannotatedTree,_sel2IlibUpdates,_sel2IoriginalTree) =
                  (sel2_ _sel2Oenv _sel2Olib )
          in  ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_SelectExpression_Select :: Annotation ->
                               T_Distinct  ->
                               T_SelectList  ->
                               T_TableRefList  ->
                               T_MaybeBoolExpression  ->
                               T_ExpressionList  ->
                               T_MaybeBoolExpression  ->
                               T_ExpressionDirectionPairList  ->
                               T_MaybeExpression  ->
                               T_MaybeExpression  ->
                               T_SelectExpression 
sem_SelectExpression_Select ann_ selDistinct_ selSelectList_ selTref_ selWhere_ selGroupBy_ selHaving_ selOrderBy_ selLimit_ selOffset_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: SelectExpression
              _selSelectListOlib :: LocalIdentifierBindings
              _selWhereOlib :: LocalIdentifierBindings
              _selGroupByOlib :: LocalIdentifierBindings
              _selOrderByOlib :: LocalIdentifierBindings
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOoriginalTree :: SelectExpression
              _selDistinctOenv :: Environment
              _selDistinctOlib :: LocalIdentifierBindings
              _selSelectListOenv :: Environment
              _selTrefOenv :: Environment
              _selTrefOlib :: LocalIdentifierBindings
              _selWhereOenv :: Environment
              _selGroupByOenv :: Environment
              _selHavingOenv :: Environment
              _selHavingOlib :: LocalIdentifierBindings
              _selOrderByOenv :: Environment
              _selLimitOenv :: Environment
              _selLimitOlib :: LocalIdentifierBindings
              _selOffsetOenv :: Environment
              _selOffsetOlib :: LocalIdentifierBindings
              _selDistinctIannotatedTree :: Distinct
              _selDistinctIoriginalTree :: Distinct
              _selSelectListIannotatedTree :: SelectList
              _selSelectListIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selSelectListIlistType :: ([(String,Type)])
              _selSelectListIoriginalTree :: SelectList
              _selTrefIannotatedTree :: TableRefList
              _selTrefIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selTrefIoriginalTree :: TableRefList
              _selWhereIannotatedTree :: MaybeBoolExpression
              _selWhereIoriginalTree :: MaybeBoolExpression
              _selGroupByIannotatedTree :: ExpressionList
              _selGroupByIoriginalTree :: ExpressionList
              _selGroupByItypeList :: ([Type])
              _selHavingIannotatedTree :: MaybeBoolExpression
              _selHavingIoriginalTree :: MaybeBoolExpression
              _selOrderByIannotatedTree :: ExpressionDirectionPairList
              _selOrderByIoriginalTree :: ExpressionDirectionPairList
              _selLimitIannotatedTree :: MaybeExpression
              _selLimitIoriginalTree :: MaybeExpression
              _selOffsetIannotatedTree :: MaybeExpression
              _selOffsetIoriginalTree :: MaybeExpression
              -- "./TypeChecking/SelectStatement.ag"(line 23, column 9)
              _lhsOannotatedTree =
                  {-# LINE 23 "./TypeChecking/SelectStatement.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    Nothing
                  {-# LINE 8091 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 94, column 10)
              _newLib =
                  {-# LINE 94 "./TypeChecking/SelectStatement.ag" #-}
                  case updateBindings _lhsIlib _lhsIenv _selTrefIlibUpdates of
                    Left x -> error $ show x
                    Right e -> e
                  {-# LINE 8098 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 97, column 10)
              _selSelectListOlib =
                  {-# LINE 97 "./TypeChecking/SelectStatement.ag" #-}
                  _newLib
                  {-# LINE 8103 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 98, column 10)
              _selWhereOlib =
                  {-# LINE 98 "./TypeChecking/SelectStatement.ag" #-}
                  _newLib
                  {-# LINE 8108 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 99, column 10)
              _selGroupByOlib =
                  {-# LINE 99 "./TypeChecking/SelectStatement.ag" #-}
                  _newLib
                  {-# LINE 8113 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 100, column 10)
              _selOrderByOlib =
                  {-# LINE 100 "./TypeChecking/SelectStatement.ag" #-}
                  _newLib
                  {-# LINE 8118 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 111, column 9)
              _tpe =
                  {-# LINE 111 "./TypeChecking/SelectStatement.ag" #-}
                  do
                  Right $ case _selSelectListIlistType of
                            [(_,Pseudo Void)] -> Pseudo Void
                            _ -> SetOfType $ CompositeType _selSelectListIlistType
                  {-# LINE 8126 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 118, column 9)
              _backTree =
                  {-# LINE 118 "./TypeChecking/SelectStatement.ag" #-}
                  Select ann_
                         _selDistinctIannotatedTree
                         _selSelectListIannotatedTree
                         _selTrefIannotatedTree
                         _selWhereIannotatedTree
                         _selGroupByIannotatedTree
                         _selHavingIannotatedTree
                         _selOrderByIannotatedTree
                         _selLimitIannotatedTree
                         _selOffsetIannotatedTree
                  {-# LINE 8140 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 85, column 9)
              _lhsOlibUpdates =
                  {-# LINE 85 "./TypeChecking/SelectLists.ag" #-}
                  _selSelectListIlibUpdates
                  {-# LINE 8145 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Select ann_ _selDistinctIannotatedTree _selSelectListIannotatedTree _selTrefIannotatedTree _selWhereIannotatedTree _selGroupByIannotatedTree _selHavingIannotatedTree _selOrderByIannotatedTree _selLimitIannotatedTree _selOffsetIannotatedTree
                  {-# LINE 8150 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Select ann_ _selDistinctIoriginalTree _selSelectListIoriginalTree _selTrefIoriginalTree _selWhereIoriginalTree _selGroupByIoriginalTree _selHavingIoriginalTree _selOrderByIoriginalTree _selLimitIoriginalTree _selOffsetIoriginalTree
                  {-# LINE 8155 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8160 "AstInternal.hs" #-}
              -- copy rule (down)
              _selDistinctOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8165 "AstInternal.hs" #-}
              -- copy rule (down)
              _selDistinctOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8170 "AstInternal.hs" #-}
              -- copy rule (down)
              _selSelectListOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8175 "AstInternal.hs" #-}
              -- copy rule (down)
              _selTrefOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8180 "AstInternal.hs" #-}
              -- copy rule (down)
              _selTrefOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8185 "AstInternal.hs" #-}
              -- copy rule (down)
              _selWhereOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8190 "AstInternal.hs" #-}
              -- copy rule (down)
              _selGroupByOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8195 "AstInternal.hs" #-}
              -- copy rule (down)
              _selHavingOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8200 "AstInternal.hs" #-}
              -- copy rule (down)
              _selHavingOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8205 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOrderByOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8210 "AstInternal.hs" #-}
              -- copy rule (down)
              _selLimitOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8215 "AstInternal.hs" #-}
              -- copy rule (down)
              _selLimitOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8220 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOffsetOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8225 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOffsetOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8230 "AstInternal.hs" #-}
              ( _selDistinctIannotatedTree,_selDistinctIoriginalTree) =
                  (selDistinct_ _selDistinctOenv _selDistinctOlib )
              ( _selSelectListIannotatedTree,_selSelectListIlibUpdates,_selSelectListIlistType,_selSelectListIoriginalTree) =
                  (selSelectList_ _selSelectListOenv _selSelectListOlib )
              ( _selTrefIannotatedTree,_selTrefIlibUpdates,_selTrefIoriginalTree) =
                  (selTref_ _selTrefOenv _selTrefOlib )
              ( _selWhereIannotatedTree,_selWhereIoriginalTree) =
                  (selWhere_ _selWhereOenv _selWhereOlib )
              ( _selGroupByIannotatedTree,_selGroupByIoriginalTree,_selGroupByItypeList) =
                  (selGroupBy_ _selGroupByOenv _selGroupByOlib )
              ( _selHavingIannotatedTree,_selHavingIoriginalTree) =
                  (selHaving_ _selHavingOenv _selHavingOlib )
              ( _selOrderByIannotatedTree,_selOrderByIoriginalTree) =
                  (selOrderBy_ _selOrderByOenv _selOrderByOlib )
              ( _selLimitIannotatedTree,_selLimitIoriginalTree) =
                  (selLimit_ _selLimitOenv _selLimitOlib )
              ( _selOffsetIannotatedTree,_selOffsetIoriginalTree) =
                  (selOffset_ _selOffsetOenv _selOffsetOlib )
          in  ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_SelectExpression_Values :: Annotation ->
                               T_ExpressionListList  ->
                               T_SelectExpression 
sem_SelectExpression_Values ann_ vll_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: SelectExpression
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOoriginalTree :: SelectExpression
              _vllOenv :: Environment
              _vllOlib :: LocalIdentifierBindings
              _vllIannotatedTree :: ExpressionListList
              _vllIoriginalTree :: ExpressionListList
              _vllItypeListList :: ([[Type]])
              -- "./TypeChecking/SelectStatement.ag"(line 23, column 9)
              _lhsOannotatedTree =
                  {-# LINE 23 "./TypeChecking/SelectStatement.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    Nothing
                  {-# LINE 8271 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 106, column 9)
              _tpe =
                  {-# LINE 106 "./TypeChecking/SelectStatement.ag" #-}
                  typeCheckValuesExpr
                              _lhsIenv
                              _vllItypeListList
                  {-# LINE 8278 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 109, column 9)
              _backTree =
                  {-# LINE 109 "./TypeChecking/SelectStatement.ag" #-}
                  Values ann_ _vllIannotatedTree
                  {-# LINE 8283 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 87, column 11)
              _lhsOlibUpdates =
                  {-# LINE 87 "./TypeChecking/SelectLists.ag" #-}
                  []
                  {-# LINE 8288 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Values ann_ _vllIannotatedTree
                  {-# LINE 8293 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Values ann_ _vllIoriginalTree
                  {-# LINE 8298 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8303 "AstInternal.hs" #-}
              -- copy rule (down)
              _vllOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8308 "AstInternal.hs" #-}
              -- copy rule (down)
              _vllOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8313 "AstInternal.hs" #-}
              ( _vllIannotatedTree,_vllIoriginalTree,_vllItypeListList) =
                  (vll_ _vllOenv _vllOlib )
          in  ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOoriginalTree)))
-- SelectItem --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         columnName           : String
         itemType             : Type
         originalTree         : SELF 
   alternatives:
      alternative SelExp:
         child ann            : {Annotation}
         child ex             : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative SelectItem:
         child ann            : {Annotation}
         child ex             : Expression 
         child name           : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data SelectItem  = SelExp (Annotation) (Expression) 
                 | SelectItem (Annotation) (Expression) (String) 
                 deriving ( Data,Eq,Show,Typeable)
-- cata
sem_SelectItem :: SelectItem  ->
                  T_SelectItem 
sem_SelectItem (SelExp _ann _ex )  =
    (sem_SelectItem_SelExp _ann (sem_Expression _ex ) )
sem_SelectItem (SelectItem _ann _ex _name )  =
    (sem_SelectItem_SelectItem _ann (sem_Expression _ex ) _name )
-- semantic domain
type T_SelectItem  = Environment ->
                     LocalIdentifierBindings ->
                     ( SelectItem,String,Type,SelectItem)
data Inh_SelectItem  = Inh_SelectItem {env_Inh_SelectItem :: Environment,lib_Inh_SelectItem :: LocalIdentifierBindings}
data Syn_SelectItem  = Syn_SelectItem {annotatedTree_Syn_SelectItem :: SelectItem,columnName_Syn_SelectItem :: String,itemType_Syn_SelectItem :: Type,originalTree_Syn_SelectItem :: SelectItem}
wrap_SelectItem :: T_SelectItem  ->
                   Inh_SelectItem  ->
                   Syn_SelectItem 
wrap_SelectItem sem (Inh_SelectItem _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOcolumnName,_lhsOitemType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_SelectItem _lhsOannotatedTree _lhsOcolumnName _lhsOitemType _lhsOoriginalTree ))
sem_SelectItem_SelExp :: Annotation ->
                         T_Expression  ->
                         T_SelectItem 
sem_SelectItem_SelExp ann_ ex_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOitemType :: Type
              _lhsOcolumnName :: String
              _lhsOannotatedTree :: SelectItem
              _lhsOoriginalTree :: SelectItem
              _exOenv :: Environment
              _exOlib :: LocalIdentifierBindings
              _exIannotatedTree :: Expression
              _exIliftedColumnName :: String
              _exIoriginalTree :: Expression
              -- "./TypeChecking/SelectLists.ag"(line 13, column 9)
              _annotatedTree =
                  {-# LINE 13 "./TypeChecking/SelectLists.ag" #-}
                  SelExp ann_ $ fixStar _exIannotatedTree
                  {-# LINE 8385 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 35, column 9)
              _lhsOitemType =
                  {-# LINE 35 "./TypeChecking/SelectLists.ag" #-}
                  getTypeAnnotation _exIannotatedTree
                  {-# LINE 8390 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 181, column 14)
              _lhsOcolumnName =
                  {-# LINE 181 "./TypeChecking/SelectLists.ag" #-}
                  case _exIliftedColumnName of
                    "" -> "?column?"
                    s -> s
                  {-# LINE 8397 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SelExp ann_ _exIoriginalTree
                  {-# LINE 8402 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 8407 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8412 "AstInternal.hs" #-}
              -- copy rule (down)
              _exOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8417 "AstInternal.hs" #-}
              -- copy rule (down)
              _exOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8422 "AstInternal.hs" #-}
              ( _exIannotatedTree,_exIliftedColumnName,_exIoriginalTree) =
                  (ex_ _exOenv _exOlib )
          in  ( _lhsOannotatedTree,_lhsOcolumnName,_lhsOitemType,_lhsOoriginalTree)))
sem_SelectItem_SelectItem :: Annotation ->
                             T_Expression  ->
                             String ->
                             T_SelectItem 
sem_SelectItem_SelectItem ann_ ex_ name_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOitemType :: Type
              _lhsOcolumnName :: String
              _lhsOannotatedTree :: SelectItem
              _lhsOoriginalTree :: SelectItem
              _exOenv :: Environment
              _exOlib :: LocalIdentifierBindings
              _exIannotatedTree :: Expression
              _exIliftedColumnName :: String
              _exIoriginalTree :: Expression
              -- "./TypeChecking/SelectLists.ag"(line 15, column 9)
              _annotatedTree =
                  {-# LINE 15 "./TypeChecking/SelectLists.ag" #-}
                  SelectItem ann_ (fixStar _exIannotatedTree) name_
                  {-# LINE 8446 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 35, column 9)
              _lhsOitemType =
                  {-# LINE 35 "./TypeChecking/SelectLists.ag" #-}
                  getTypeAnnotation _exIannotatedTree
                  {-# LINE 8451 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 184, column 18)
              _lhsOcolumnName =
                  {-# LINE 184 "./TypeChecking/SelectLists.ag" #-}
                  name_
                  {-# LINE 8456 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SelectItem ann_ _exIoriginalTree name_
                  {-# LINE 8461 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 8466 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8471 "AstInternal.hs" #-}
              -- copy rule (down)
              _exOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8476 "AstInternal.hs" #-}
              -- copy rule (down)
              _exOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8481 "AstInternal.hs" #-}
              ( _exIannotatedTree,_exIliftedColumnName,_exIoriginalTree) =
                  (ex_ _exOenv _exOlib )
          in  ( _lhsOannotatedTree,_lhsOcolumnName,_lhsOitemType,_lhsOoriginalTree)))
-- SelectItemList ----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         listType             : [(String,Type)]
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : SelectItem 
         child tl             : SelectItemList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type SelectItemList  = [(SelectItem)]
-- cata
sem_SelectItemList :: SelectItemList  ->
                      T_SelectItemList 
sem_SelectItemList list  =
    (Prelude.foldr sem_SelectItemList_Cons sem_SelectItemList_Nil (Prelude.map sem_SelectItem list) )
-- semantic domain
type T_SelectItemList  = Environment ->
                         LocalIdentifierBindings ->
                         ( SelectItemList,([(String,Type)]),SelectItemList)
data Inh_SelectItemList  = Inh_SelectItemList {env_Inh_SelectItemList :: Environment,lib_Inh_SelectItemList :: LocalIdentifierBindings}
data Syn_SelectItemList  = Syn_SelectItemList {annotatedTree_Syn_SelectItemList :: SelectItemList,listType_Syn_SelectItemList :: [(String,Type)],originalTree_Syn_SelectItemList :: SelectItemList}
wrap_SelectItemList :: T_SelectItemList  ->
                       Inh_SelectItemList  ->
                       Syn_SelectItemList 
wrap_SelectItemList sem (Inh_SelectItemList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_SelectItemList _lhsOannotatedTree _lhsOlistType _lhsOoriginalTree ))
sem_SelectItemList_Cons :: T_SelectItem  ->
                           T_SelectItemList  ->
                           T_SelectItemList 
sem_SelectItemList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlistType :: ([(String,Type)])
              _lhsOannotatedTree :: SelectItemList
              _lhsOoriginalTree :: SelectItemList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: SelectItem
              _hdIcolumnName :: String
              _hdIitemType :: Type
              _hdIoriginalTree :: SelectItem
              _tlIannotatedTree :: SelectItemList
              _tlIlistType :: ([(String,Type)])
              _tlIoriginalTree :: SelectItemList
              -- "./TypeChecking/SelectLists.ag"(line 29, column 12)
              _lhsOlistType =
                  {-# LINE 29 "./TypeChecking/SelectLists.ag" #-}
                  expandStar _lhsIlib _hdIcolumnName _hdIitemType _tlIlistType
                  {-# LINE 8550 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 8555 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 8560 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 8565 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8570 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8575 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8580 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8585 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8590 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIcolumnName,_hdIitemType,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIlistType,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree)))
sem_SelectItemList_Nil :: T_SelectItemList 
sem_SelectItemList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlistType :: ([(String,Type)])
              _lhsOannotatedTree :: SelectItemList
              _lhsOoriginalTree :: SelectItemList
              -- "./TypeChecking/SelectLists.ag"(line 30, column 11)
              _lhsOlistType =
                  {-# LINE 30 "./TypeChecking/SelectLists.ag" #-}
                  []
                  {-# LINE 8607 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 8612 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 8617 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 8622 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8627 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOlistType,_lhsOoriginalTree)))
-- SelectList --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         libUpdates           : [LocalIdentifierBindingsUpdate]
         listType             : [(String,Type)]
         originalTree         : SELF 
   alternatives:
      alternative SelectList:
         child ann            : {Annotation}
         child items          : SelectItemList 
         child into           : StringList 
         visit 0:
            local errs        : _
            local stuff       : _
            local annotatedTree : _
            local originalTree : _
-}
data SelectList  = SelectList (Annotation) (SelectItemList) (StringList) 
                 deriving ( Data,Eq,Show,Typeable)
-- cata
sem_SelectList :: SelectList  ->
                  T_SelectList 
sem_SelectList (SelectList _ann _items _into )  =
    (sem_SelectList_SelectList _ann (sem_SelectItemList _items ) (sem_StringList _into ) )
-- semantic domain
type T_SelectList  = Environment ->
                     LocalIdentifierBindings ->
                     ( SelectList,([LocalIdentifierBindingsUpdate]),([(String,Type)]),SelectList)
data Inh_SelectList  = Inh_SelectList {env_Inh_SelectList :: Environment,lib_Inh_SelectList :: LocalIdentifierBindings}
data Syn_SelectList  = Syn_SelectList {annotatedTree_Syn_SelectList :: SelectList,libUpdates_Syn_SelectList :: [LocalIdentifierBindingsUpdate],listType_Syn_SelectList :: [(String,Type)],originalTree_Syn_SelectList :: SelectList}
wrap_SelectList :: T_SelectList  ->
                   Inh_SelectList  ->
                   Syn_SelectList 
wrap_SelectList sem (Inh_SelectList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOlistType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_SelectList _lhsOannotatedTree _lhsOlibUpdates _lhsOlistType _lhsOoriginalTree ))
sem_SelectList_SelectList :: Annotation ->
                             T_SelectItemList  ->
                             T_StringList  ->
                             T_SelectList 
sem_SelectList_SelectList ann_ items_ into_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlistType :: ([(String,Type)])
              _lhsOannotatedTree :: SelectList
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOoriginalTree :: SelectList
              _itemsOenv :: Environment
              _itemsOlib :: LocalIdentifierBindings
              _intoOenv :: Environment
              _intoOlib :: LocalIdentifierBindings
              _itemsIannotatedTree :: SelectItemList
              _itemsIlistType :: ([(String,Type)])
              _itemsIoriginalTree :: SelectItemList
              _intoIannotatedTree :: StringList
              _intoIoriginalTree :: StringList
              _intoIstrings :: ([String])
              -- "./TypeChecking/SelectLists.ag"(line 41, column 9)
              _lhsOlistType =
                  {-# LINE 41 "./TypeChecking/SelectLists.ag" #-}
                  _itemsIlistType
                  {-# LINE 8696 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 43, column 9)
              _errs =
                  {-# LINE 43 "./TypeChecking/SelectLists.ag" #-}
                  case _stuff     of
                    (er,_) -> er
                  {-# LINE 8702 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 45, column 9)
              _stuff =
                  {-# LINE 45 "./TypeChecking/SelectLists.ag" #-}
                  case () of
                    _ | null sl -> ([],Nothing)
                      | not (null targetTypeErrs) -> (targetTypeErrs,Nothing)
                      | (case targetTypes of
                           [PgRecord _] -> True
                           _ -> False) -> ([],Just (head sl, CompositeType _itemsIlistType))
                      | matchingComposite /= Left [] -> (fromLeft [] matchingComposite,Nothing)
                      | length sl /= length _itemsIlistType -> ([WrongNumberOfColumns],Nothing)
                      | not (null assignErrs) -> (assignErrs,Nothing)
                      | otherwise -> ([],Nothing)
                  where
                    targetTypeEithers = map (libLookupID _lhsIlib) sl
                    targetTypeErrs = concat $ lefts $ targetTypeEithers
                    targetTypes = rights $ targetTypeEithers
                    typePairs = zip (map snd _itemsIlistType) targetTypes
                    assignErrs = concat $ lefts $ map (uncurry $ checkAssignmentValid _lhsIenv) typePairs
                    sl = _intoIstrings
                    matchingComposite =
                        case targetTypes of
                          [t] | isCompositeType t -> checkAssignmentValid _lhsIenv (AnonymousRecordType (map snd _itemsIlistType)) t
                          _ -> Left []
                  {-# LINE 8727 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 68, column 9)
              _lhsOannotatedTree =
                  {-# LINE 68 "./TypeChecking/SelectLists.ag" #-}
                  SelectList (ann_ ++ map TypeErrorA _errs    )
                             _itemsIannotatedTree
                             _intoIannotatedTree
                  {-# LINE 8734 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 71, column 9)
              _lhsOlibUpdates =
                  {-# LINE 71 "./TypeChecking/SelectLists.ag" #-}
                  case _stuff     of
                    (_,Just r) -> [LibStackIDs [("", [r])]]
                    _ -> []
                  {-# LINE 8741 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SelectList ann_ _itemsIannotatedTree _intoIannotatedTree
                  {-# LINE 8746 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SelectList ann_ _itemsIoriginalTree _intoIoriginalTree
                  {-# LINE 8751 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8756 "AstInternal.hs" #-}
              -- copy rule (down)
              _itemsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8761 "AstInternal.hs" #-}
              -- copy rule (down)
              _itemsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8766 "AstInternal.hs" #-}
              -- copy rule (down)
              _intoOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8771 "AstInternal.hs" #-}
              -- copy rule (down)
              _intoOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8776 "AstInternal.hs" #-}
              ( _itemsIannotatedTree,_itemsIlistType,_itemsIoriginalTree) =
                  (items_ _itemsOenv _itemsOlib )
              ( _intoIannotatedTree,_intoIoriginalTree,_intoIstrings) =
                  (into_ _intoOenv _intoOlib )
          in  ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOlistType,_lhsOoriginalTree)))
-- SetClause ---------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         pairs                : [(String,Type)]
         rowSetError          : Maybe TypeError
   alternatives:
      alternative RowSetClause:
         child ann            : {Annotation}
         child atts           : StringList 
         child vals           : ExpressionList 
         visit 0:
            local rowSetError : _
            local annotatedTree : _
            local originalTree : _
      alternative SetClause:
         child ann            : {Annotation}
         child att            : {String}
         child val            : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data SetClause  = RowSetClause (Annotation) (StringList) (ExpressionList) 
                | SetClause (Annotation) (String) (Expression) 
                deriving ( Data,Eq,Show,Typeable)
-- cata
sem_SetClause :: SetClause  ->
                 T_SetClause 
sem_SetClause (RowSetClause _ann _atts _vals )  =
    (sem_SetClause_RowSetClause _ann (sem_StringList _atts ) (sem_ExpressionList _vals ) )
sem_SetClause (SetClause _ann _att _val )  =
    (sem_SetClause_SetClause _ann _att (sem_Expression _val ) )
-- semantic domain
type T_SetClause  = Environment ->
                    LocalIdentifierBindings ->
                    ( SetClause,SetClause,([(String,Type)]),(Maybe TypeError))
data Inh_SetClause  = Inh_SetClause {env_Inh_SetClause :: Environment,lib_Inh_SetClause :: LocalIdentifierBindings}
data Syn_SetClause  = Syn_SetClause {annotatedTree_Syn_SetClause :: SetClause,originalTree_Syn_SetClause :: SetClause,pairs_Syn_SetClause :: [(String,Type)],rowSetError_Syn_SetClause :: Maybe TypeError}
wrap_SetClause :: T_SetClause  ->
                  Inh_SetClause  ->
                  Syn_SetClause 
wrap_SetClause sem (Inh_SetClause _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOpairs,_lhsOrowSetError) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_SetClause _lhsOannotatedTree _lhsOoriginalTree _lhsOpairs _lhsOrowSetError ))
sem_SetClause_RowSetClause :: Annotation ->
                              T_StringList  ->
                              T_ExpressionList  ->
                              T_SetClause 
sem_SetClause_RowSetClause ann_ atts_ vals_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOpairs :: ([(String,Type)])
              _lhsOannotatedTree :: SetClause
              _lhsOoriginalTree :: SetClause
              _lhsOrowSetError :: (Maybe TypeError)
              _attsOenv :: Environment
              _attsOlib :: LocalIdentifierBindings
              _valsOenv :: Environment
              _valsOlib :: LocalIdentifierBindings
              _attsIannotatedTree :: StringList
              _attsIoriginalTree :: StringList
              _attsIstrings :: ([String])
              _valsIannotatedTree :: ExpressionList
              _valsIoriginalTree :: ExpressionList
              _valsItypeList :: ([Type])
              -- "./TypeChecking/Dml.ag"(line 128, column 9)
              _rowSetError =
                  {-# LINE 128 "./TypeChecking/Dml.ag" #-}
                  let atts = _attsIstrings
                      types = getRowTypes _valsItypeList
                  in if length atts /= length types
                       then Just WrongNumberOfColumns
                       else Nothing
                  {-# LINE 8862 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 134, column 9)
              _lhsOpairs =
                  {-# LINE 134 "./TypeChecking/Dml.ag" #-}
                  zip _attsIstrings $ getRowTypes _valsItypeList
                  {-# LINE 8867 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  RowSetClause ann_ _attsIannotatedTree _valsIannotatedTree
                  {-# LINE 8872 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  RowSetClause ann_ _attsIoriginalTree _valsIoriginalTree
                  {-# LINE 8877 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 8882 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8887 "AstInternal.hs" #-}
              -- copy rule (from local)
              _lhsOrowSetError =
                  {-# LINE 121 "./TypeChecking/Dml.ag" #-}
                  _rowSetError
                  {-# LINE 8892 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8897 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8902 "AstInternal.hs" #-}
              -- copy rule (down)
              _valsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8907 "AstInternal.hs" #-}
              -- copy rule (down)
              _valsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8912 "AstInternal.hs" #-}
              ( _attsIannotatedTree,_attsIoriginalTree,_attsIstrings) =
                  (atts_ _attsOenv _attsOlib )
              ( _valsIannotatedTree,_valsIoriginalTree,_valsItypeList) =
                  (vals_ _valsOenv _valsOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOpairs,_lhsOrowSetError)))
sem_SetClause_SetClause :: Annotation ->
                           String ->
                           T_Expression  ->
                           T_SetClause 
sem_SetClause_SetClause ann_ att_ val_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOpairs :: ([(String,Type)])
              _lhsOrowSetError :: (Maybe TypeError)
              _lhsOannotatedTree :: SetClause
              _lhsOoriginalTree :: SetClause
              _valOenv :: Environment
              _valOlib :: LocalIdentifierBindings
              _valIannotatedTree :: Expression
              _valIliftedColumnName :: String
              _valIoriginalTree :: Expression
              -- "./TypeChecking/Dml.ag"(line 125, column 9)
              _lhsOpairs =
                  {-# LINE 125 "./TypeChecking/Dml.ag" #-}
                  [(att_, getTypeAnnotation _valIannotatedTree)]
                  {-# LINE 8938 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 126, column 9)
              _lhsOrowSetError =
                  {-# LINE 126 "./TypeChecking/Dml.ag" #-}
                  Nothing
                  {-# LINE 8943 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SetClause ann_ att_ _valIannotatedTree
                  {-# LINE 8948 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SetClause ann_ att_ _valIoriginalTree
                  {-# LINE 8953 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 8958 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 8963 "AstInternal.hs" #-}
              -- copy rule (down)
              _valOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 8968 "AstInternal.hs" #-}
              -- copy rule (down)
              _valOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 8973 "AstInternal.hs" #-}
              ( _valIannotatedTree,_valIliftedColumnName,_valIoriginalTree) =
                  (val_ _valOenv _valOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOpairs,_lhsOrowSetError)))
-- SetClauseList -----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         pairs                : [(String,Type)]
         rowSetErrors         : [TypeError]
   alternatives:
      alternative Cons:
         child hd             : SetClause 
         child tl             : SetClauseList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type SetClauseList  = [(SetClause)]
-- cata
sem_SetClauseList :: SetClauseList  ->
                     T_SetClauseList 
sem_SetClauseList list  =
    (Prelude.foldr sem_SetClauseList_Cons sem_SetClauseList_Nil (Prelude.map sem_SetClause list) )
-- semantic domain
type T_SetClauseList  = Environment ->
                        LocalIdentifierBindings ->
                        ( SetClauseList,SetClauseList,([(String,Type)]),([TypeError]))
data Inh_SetClauseList  = Inh_SetClauseList {env_Inh_SetClauseList :: Environment,lib_Inh_SetClauseList :: LocalIdentifierBindings}
data Syn_SetClauseList  = Syn_SetClauseList {annotatedTree_Syn_SetClauseList :: SetClauseList,originalTree_Syn_SetClauseList :: SetClauseList,pairs_Syn_SetClauseList :: [(String,Type)],rowSetErrors_Syn_SetClauseList :: [TypeError]}
wrap_SetClauseList :: T_SetClauseList  ->
                      Inh_SetClauseList  ->
                      Syn_SetClauseList 
wrap_SetClauseList sem (Inh_SetClauseList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOpairs,_lhsOrowSetErrors) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_SetClauseList _lhsOannotatedTree _lhsOoriginalTree _lhsOpairs _lhsOrowSetErrors ))
sem_SetClauseList_Cons :: T_SetClause  ->
                          T_SetClauseList  ->
                          T_SetClauseList 
sem_SetClauseList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOpairs :: ([(String,Type)])
              _lhsOrowSetErrors :: ([TypeError])
              _lhsOannotatedTree :: SetClauseList
              _lhsOoriginalTree :: SetClauseList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: SetClause
              _hdIoriginalTree :: SetClause
              _hdIpairs :: ([(String,Type)])
              _hdIrowSetError :: (Maybe TypeError)
              _tlIannotatedTree :: SetClauseList
              _tlIoriginalTree :: SetClauseList
              _tlIpairs :: ([(String,Type)])
              _tlIrowSetErrors :: ([TypeError])
              -- "./TypeChecking/Dml.ag"(line 115, column 10)
              _lhsOpairs =
                  {-# LINE 115 "./TypeChecking/Dml.ag" #-}
                  _hdIpairs ++ _tlIpairs
                  {-# LINE 9045 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 116, column 10)
              _lhsOrowSetErrors =
                  {-# LINE 116 "./TypeChecking/Dml.ag" #-}
                  maybeToList _hdIrowSetError ++ _tlIrowSetErrors
                  {-# LINE 9050 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 9055 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 9060 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 9065 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9070 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 9075 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 9080 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 9085 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 9090 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIoriginalTree,_hdIpairs,_hdIrowSetError) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree,_tlIpairs,_tlIrowSetErrors) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOpairs,_lhsOrowSetErrors)))
sem_SetClauseList_Nil :: T_SetClauseList 
sem_SetClauseList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOpairs :: ([(String,Type)])
              _lhsOrowSetErrors :: ([TypeError])
              _lhsOannotatedTree :: SetClauseList
              _lhsOoriginalTree :: SetClauseList
              -- "./TypeChecking/Dml.ag"(line 117, column 9)
              _lhsOpairs =
                  {-# LINE 117 "./TypeChecking/Dml.ag" #-}
                  []
                  {-# LINE 9108 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 118, column 9)
              _lhsOrowSetErrors =
                  {-# LINE 118 "./TypeChecking/Dml.ag" #-}
                  []
                  {-# LINE 9113 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 9118 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 9123 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 9128 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9133 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOpairs,_lhsOrowSetErrors)))
-- SetValue ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative SetId:
         child ann            : {Annotation}
         child string         : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative SetNum:
         child ann            : {Annotation}
         child double         : {Double}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative SetStr:
         child ann            : {Annotation}
         child string         : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data SetValue  = SetId (Annotation) (String) 
               | SetNum (Annotation) (Double) 
               | SetStr (Annotation) (String) 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_SetValue :: SetValue  ->
                T_SetValue 
sem_SetValue (SetId _ann _string )  =
    (sem_SetValue_SetId _ann _string )
sem_SetValue (SetNum _ann _double )  =
    (sem_SetValue_SetNum _ann _double )
sem_SetValue (SetStr _ann _string )  =
    (sem_SetValue_SetStr _ann _string )
-- semantic domain
type T_SetValue  = Environment ->
                   LocalIdentifierBindings ->
                   ( SetValue,SetValue)
data Inh_SetValue  = Inh_SetValue {env_Inh_SetValue :: Environment,lib_Inh_SetValue :: LocalIdentifierBindings}
data Syn_SetValue  = Syn_SetValue {annotatedTree_Syn_SetValue :: SetValue,originalTree_Syn_SetValue :: SetValue}
wrap_SetValue :: T_SetValue  ->
                 Inh_SetValue  ->
                 Syn_SetValue 
wrap_SetValue sem (Inh_SetValue _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_SetValue _lhsOannotatedTree _lhsOoriginalTree ))
sem_SetValue_SetId :: Annotation ->
                      String ->
                      T_SetValue 
sem_SetValue_SetId ann_ string_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: SetValue
              _lhsOoriginalTree :: SetValue
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SetId ann_ string_
                  {-# LINE 9202 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SetId ann_ string_
                  {-# LINE 9207 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 9212 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9217 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_SetValue_SetNum :: Annotation ->
                       Double ->
                       T_SetValue 
sem_SetValue_SetNum ann_ double_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: SetValue
              _lhsOoriginalTree :: SetValue
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SetNum ann_ double_
                  {-# LINE 9231 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SetNum ann_ double_
                  {-# LINE 9236 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 9241 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9246 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_SetValue_SetStr :: Annotation ->
                       String ->
                       T_SetValue 
sem_SetValue_SetStr ann_ string_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: SetValue
              _lhsOoriginalTree :: SetValue
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SetStr ann_ string_
                  {-# LINE 9260 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SetStr ann_ string_
                  {-# LINE 9265 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 9270 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9275 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- Statement ---------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         inProducedEnv        : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         envUpdates           : [EnvironmentUpdate]
         libUpdates           : [LocalIdentifierBindingsUpdate]
         originalTree         : SELF 
   alternatives:
      alternative AlterSequence:
         child ann            : {Annotation}
         child name           : {String}
         child ownedBy        : {String}
         visit 0:
            local libUpdates  : _
            local annotatedTree : _
            local originalTree : _
      alternative AlterTable:
         child ann            : {Annotation}
         child name           : {String}
         child actions        : {[AlterTableAction]}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Assignment:
         child ann            : {Annotation}
         child target         : {String}
         child value          : Expression 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative CaseStatement:
         child ann            : {Annotation}
         child val            : Expression 
         child cases          : ExpressionListStatementListPairList 
         child els            : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative ContinueStatement:
         child ann            : {Annotation}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Copy:
         child ann            : {Annotation}
         child table          : {String}
         child targetCols     : StringList 
         child source         : CopySource 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative CopyData:
         child ann            : {Annotation}
         child insData        : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative CreateDomain:
         child ann            : {Annotation}
         child name           : {String}
         child typ            : TypeName 
         child checkName      : {String}
         child check          : MaybeBoolExpression 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local statementType : _
            local envUpdates  : {[EnvironmentUpdate]}
            local annotatedTree : _
            local originalTree : _
      alternative CreateFunction:
         child ann            : {Annotation}
         child name           : {String}
         child params         : ParamDefList 
         child rettype        : TypeName 
         child lang           : Language 
         child bodyQuote      : {String}
         child body           : FnBody 
         child vol            : Volatility 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local envUpdates  : {[EnvironmentUpdate]}
            local parameterTypes : _
            local backTree    : _
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative CreateLanguage:
         child ann            : {Annotation}
         child name           : {String}
         visit 0:
            local libUpdates  : _
            local annotatedTree : _
            local originalTree : _
      alternative CreateSequence:
         child ann            : {Annotation}
         child name           : {String}
         child incr           : {Integer}
         child min            : {Integer}
         child max            : {Integer}
         child start          : {Integer}
         child cache          : {Integer}
         visit 0:
            local libUpdates  : _
            local annotatedTree : _
            local originalTree : _
      alternative CreateTable:
         child ann            : {Annotation}
         child name           : {String}
         child atts           : AttributeDefList 
         child cons           : ConstraintList 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local envUpdates  : {[EnvironmentUpdate]}
            local attrTypes   : {[Type]}
            local statementType : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative CreateTableAs:
         child ann            : {Annotation}
         child name           : {String}
         child expr           : SelectExpression 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local envUpdates  : {[EnvironmentUpdate]}
            local selType     : _
            local attrs       : _
            local backTree    : _
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative CreateTrigger:
         child ann            : {Annotation}
         child name           : {String}
         child wh             : TriggerWhen 
         child events         : {[TriggerEvent]}
         child tbl            : {String}
         child firing         : TriggerFire 
         child fnName         : {String}
         child fnArgs         : {[Expression]}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative CreateType:
         child ann            : {Annotation}
         child name           : {String}
         child atts           : TypeAttributeDefList 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local statementType : _
            local envUpdates  : {[EnvironmentUpdate]}
            local annotatedTree : _
            local originalTree : _
      alternative CreateView:
         child ann            : {Annotation}
         child name           : {String}
         child expr           : SelectExpression 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local attrs       : _
            local envUpdates  : {[EnvironmentUpdate]}
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative Delete:
         child ann            : {Annotation}
         child table          : {String}
         child whr            : MaybeBoolExpression 
         child returning      : MaybeSelectList 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local statementType : _
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local lib         : _
            local annotatedTree : _
            local originalTree : _
      alternative DropFunction:
         child ann            : {Annotation}
         child ifE            : IfExists 
         child sigs           : StringTypeNameListPairList 
         child cascade        : Cascade 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative DropSomething:
         child ann            : {Annotation}
         child dropType       : DropType 
         child ifE            : IfExists 
         child names          : StringList 
         child cascade        : Cascade 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Execute:
         child ann            : {Annotation}
         child expr           : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative ExecuteInto:
         child ann            : {Annotation}
         child expr           : Expression 
         child targets        : StringList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative ForIntegerStatement:
         child ann            : {Annotation}
         child var            : {String}
         child from           : Expression 
         child to             : Expression 
         child sts            : StatementList 
         visit 0:
            local libUpdates  : _
            local varTypeE    : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative ForSelectStatement:
         child ann            : {Annotation}
         child var            : {String}
         child sel            : SelectExpression 
         child sts            : StatementList 
         visit 0:
            local libUpdates  : _
            local selType     : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative If:
         child ann            : {Annotation}
         child cases          : ExpressionStatementListPairList 
         child els            : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Insert:
         child ann            : {Annotation}
         child table          : {String}
         child targetCols     : StringList 
         child insData        : SelectExpression 
         child returning      : MaybeSelectList 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local statementType : _
            local columnTypes : _
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local annotatedTree : _
            local originalTree : _
      alternative Notify:
         child ann            : {Annotation}
         child name           : {String}
         visit 0:
            local libUpdates  : _
            local annotatedTree : _
            local originalTree : _
      alternative NullStatement:
         child ann            : {Annotation}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Perform:
         child ann            : {Annotation}
         child expr           : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Raise:
         child ann            : {Annotation}
         child level          : RaiseType 
         child message        : {String}
         child args           : ExpressionList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Return:
         child ann            : {Annotation}
         child value          : MaybeExpression 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local statementType : _
            local annotatedTree : _
            local originalTree : _
      alternative ReturnNext:
         child ann            : {Annotation}
         child expr           : Expression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative ReturnQuery:
         child ann            : {Annotation}
         child sel            : SelectExpression 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative SelectStatement:
         child ann            : {Annotation}
         child ex             : SelectExpression 
         visit 0:
            local tpe         : {Either [TypeError] Type}
            local statementType : _
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local libUpdates  : _
            local annotatedTree : _
            local originalTree : _
      alternative Set:
         child ann            : {Annotation}
         child name           : {String}
         child values         : {[SetValue]}
         visit 0:
            local libUpdates  : _
            local annotatedTree : _
            local originalTree : _
      alternative Truncate:
         child ann            : {Annotation}
         child tables         : StringList 
         child restartIdentity : RestartIdentity 
         child cascade        : Cascade 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Update:
         child ann            : {Annotation}
         child table          : {String}
         child assigns        : SetClauseList 
         child whr            : MaybeBoolExpression 
         child returning      : MaybeSelectList 
         visit 0:
            local libUpdates  : _
            local tpe         : {Either [TypeError] Type}
            local statementType : _
            local columnTypes : _
            local backTree    : _
            local envUpdates  : {[EnvironmentUpdate]}
            local lib         : _
            local annotatedTree : _
            local originalTree : _
      alternative WhileStatement:
         child ann            : {Annotation}
         child expr           : Expression 
         child sts            : StatementList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Statement  = AlterSequence (Annotation) (String) (String) 
                | AlterTable (Annotation) (String) ([AlterTableAction]) 
                | Assignment (Annotation) (String) (Expression) 
                | CaseStatement (Annotation) (Expression) (ExpressionListStatementListPairList) (StatementList) 
                | ContinueStatement (Annotation) 
                | Copy (Annotation) (String) (StringList) (CopySource) 
                | CopyData (Annotation) (String) 
                | CreateDomain (Annotation) (String) (TypeName) (String) (MaybeBoolExpression) 
                | CreateFunction (Annotation) (String) (ParamDefList) (TypeName) (Language) (String) (FnBody) (Volatility) 
                | CreateLanguage (Annotation) (String) 
                | CreateSequence (Annotation) (String) (Integer) (Integer) (Integer) (Integer) (Integer) 
                | CreateTable (Annotation) (String) (AttributeDefList) (ConstraintList) 
                | CreateTableAs (Annotation) (String) (SelectExpression) 
                | CreateTrigger (Annotation) (String) (TriggerWhen) ([TriggerEvent]) (String) (TriggerFire) (String) ([Expression]) 
                | CreateType (Annotation) (String) (TypeAttributeDefList) 
                | CreateView (Annotation) (String) (SelectExpression) 
                | Delete (Annotation) (String) (MaybeBoolExpression) (MaybeSelectList) 
                | DropFunction (Annotation) (IfExists) (StringTypeNameListPairList) (Cascade) 
                | DropSomething (Annotation) (DropType) (IfExists) (StringList) (Cascade) 
                | Execute (Annotation) (Expression) 
                | ExecuteInto (Annotation) (Expression) (StringList) 
                | ForIntegerStatement (Annotation) (String) (Expression) (Expression) (StatementList) 
                | ForSelectStatement (Annotation) (String) (SelectExpression) (StatementList) 
                | If (Annotation) (ExpressionStatementListPairList) (StatementList) 
                | Insert (Annotation) (String) (StringList) (SelectExpression) (MaybeSelectList) 
                | Notify (Annotation) (String) 
                | NullStatement (Annotation) 
                | Perform (Annotation) (Expression) 
                | Raise (Annotation) (RaiseType) (String) (ExpressionList) 
                | Return (Annotation) (MaybeExpression) 
                | ReturnNext (Annotation) (Expression) 
                | ReturnQuery (Annotation) (SelectExpression) 
                | SelectStatement (Annotation) (SelectExpression) 
                | Set (Annotation) (String) ([SetValue]) 
                | Truncate (Annotation) (StringList) (RestartIdentity) (Cascade) 
                | Update (Annotation) (String) (SetClauseList) (MaybeBoolExpression) (MaybeSelectList) 
                | WhileStatement (Annotation) (Expression) (StatementList) 
                deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Statement :: Statement  ->
                 T_Statement 
sem_Statement (AlterSequence _ann _name _ownedBy )  =
    (sem_Statement_AlterSequence _ann _name _ownedBy )
sem_Statement (AlterTable _ann _name _actions )  =
    (sem_Statement_AlterTable _ann _name _actions )
sem_Statement (Assignment _ann _target _value )  =
    (sem_Statement_Assignment _ann _target (sem_Expression _value ) )
sem_Statement (CaseStatement _ann _val _cases _els )  =
    (sem_Statement_CaseStatement _ann (sem_Expression _val ) (sem_ExpressionListStatementListPairList _cases ) (sem_StatementList _els ) )
sem_Statement (ContinueStatement _ann )  =
    (sem_Statement_ContinueStatement _ann )
sem_Statement (Copy _ann _table _targetCols _source )  =
    (sem_Statement_Copy _ann _table (sem_StringList _targetCols ) (sem_CopySource _source ) )
sem_Statement (CopyData _ann _insData )  =
    (sem_Statement_CopyData _ann _insData )
sem_Statement (CreateDomain _ann _name _typ _checkName _check )  =
    (sem_Statement_CreateDomain _ann _name (sem_TypeName _typ ) _checkName (sem_MaybeBoolExpression _check ) )
sem_Statement (CreateFunction _ann _name _params _rettype _lang _bodyQuote _body _vol )  =
    (sem_Statement_CreateFunction _ann _name (sem_ParamDefList _params ) (sem_TypeName _rettype ) (sem_Language _lang ) _bodyQuote (sem_FnBody _body ) (sem_Volatility _vol ) )
sem_Statement (CreateLanguage _ann _name )  =
    (sem_Statement_CreateLanguage _ann _name )
sem_Statement (CreateSequence _ann _name _incr _min _max _start _cache )  =
    (sem_Statement_CreateSequence _ann _name _incr _min _max _start _cache )
sem_Statement (CreateTable _ann _name _atts _cons )  =
    (sem_Statement_CreateTable _ann _name (sem_AttributeDefList _atts ) (sem_ConstraintList _cons ) )
sem_Statement (CreateTableAs _ann _name _expr )  =
    (sem_Statement_CreateTableAs _ann _name (sem_SelectExpression _expr ) )
sem_Statement (CreateTrigger _ann _name _wh _events _tbl _firing _fnName _fnArgs )  =
    (sem_Statement_CreateTrigger _ann _name (sem_TriggerWhen _wh ) _events _tbl (sem_TriggerFire _firing ) _fnName _fnArgs )
sem_Statement (CreateType _ann _name _atts )  =
    (sem_Statement_CreateType _ann _name (sem_TypeAttributeDefList _atts ) )
sem_Statement (CreateView _ann _name _expr )  =
    (sem_Statement_CreateView _ann _name (sem_SelectExpression _expr ) )
sem_Statement (Delete _ann _table _whr _returning )  =
    (sem_Statement_Delete _ann _table (sem_MaybeBoolExpression _whr ) (sem_MaybeSelectList _returning ) )
sem_Statement (DropFunction _ann _ifE _sigs _cascade )  =
    (sem_Statement_DropFunction _ann (sem_IfExists _ifE ) (sem_StringTypeNameListPairList _sigs ) (sem_Cascade _cascade ) )
sem_Statement (DropSomething _ann _dropType _ifE _names _cascade )  =
    (sem_Statement_DropSomething _ann (sem_DropType _dropType ) (sem_IfExists _ifE ) (sem_StringList _names ) (sem_Cascade _cascade ) )
sem_Statement (Execute _ann _expr )  =
    (sem_Statement_Execute _ann (sem_Expression _expr ) )
sem_Statement (ExecuteInto _ann _expr _targets )  =
    (sem_Statement_ExecuteInto _ann (sem_Expression _expr ) (sem_StringList _targets ) )
sem_Statement (ForIntegerStatement _ann _var _from _to _sts )  =
    (sem_Statement_ForIntegerStatement _ann _var (sem_Expression _from ) (sem_Expression _to ) (sem_StatementList _sts ) )
sem_Statement (ForSelectStatement _ann _var _sel _sts )  =
    (sem_Statement_ForSelectStatement _ann _var (sem_SelectExpression _sel ) (sem_StatementList _sts ) )
sem_Statement (If _ann _cases _els )  =
    (sem_Statement_If _ann (sem_ExpressionStatementListPairList _cases ) (sem_StatementList _els ) )
sem_Statement (Insert _ann _table _targetCols _insData _returning )  =
    (sem_Statement_Insert _ann _table (sem_StringList _targetCols ) (sem_SelectExpression _insData ) (sem_MaybeSelectList _returning ) )
sem_Statement (Notify _ann _name )  =
    (sem_Statement_Notify _ann _name )
sem_Statement (NullStatement _ann )  =
    (sem_Statement_NullStatement _ann )
sem_Statement (Perform _ann _expr )  =
    (sem_Statement_Perform _ann (sem_Expression _expr ) )
sem_Statement (Raise _ann _level _message _args )  =
    (sem_Statement_Raise _ann (sem_RaiseType _level ) _message (sem_ExpressionList _args ) )
sem_Statement (Return _ann _value )  =
    (sem_Statement_Return _ann (sem_MaybeExpression _value ) )
sem_Statement (ReturnNext _ann _expr )  =
    (sem_Statement_ReturnNext _ann (sem_Expression _expr ) )
sem_Statement (ReturnQuery _ann _sel )  =
    (sem_Statement_ReturnQuery _ann (sem_SelectExpression _sel ) )
sem_Statement (SelectStatement _ann _ex )  =
    (sem_Statement_SelectStatement _ann (sem_SelectExpression _ex ) )
sem_Statement (Set _ann _name _values )  =
    (sem_Statement_Set _ann _name _values )
sem_Statement (Truncate _ann _tables _restartIdentity _cascade )  =
    (sem_Statement_Truncate _ann (sem_StringList _tables ) (sem_RestartIdentity _restartIdentity ) (sem_Cascade _cascade ) )
sem_Statement (Update _ann _table _assigns _whr _returning )  =
    (sem_Statement_Update _ann _table (sem_SetClauseList _assigns ) (sem_MaybeBoolExpression _whr ) (sem_MaybeSelectList _returning ) )
sem_Statement (WhileStatement _ann _expr _sts )  =
    (sem_Statement_WhileStatement _ann (sem_Expression _expr ) (sem_StatementList _sts ) )
-- semantic domain
type T_Statement  = Environment ->
                    Environment ->
                    LocalIdentifierBindings ->
                    ( Statement,([EnvironmentUpdate]),([LocalIdentifierBindingsUpdate]),Statement)
data Inh_Statement  = Inh_Statement {env_Inh_Statement :: Environment,inProducedEnv_Inh_Statement :: Environment,lib_Inh_Statement :: LocalIdentifierBindings}
data Syn_Statement  = Syn_Statement {annotatedTree_Syn_Statement :: Statement,envUpdates_Syn_Statement :: [EnvironmentUpdate],libUpdates_Syn_Statement :: [LocalIdentifierBindingsUpdate],originalTree_Syn_Statement :: Statement}
wrap_Statement :: T_Statement  ->
                  Inh_Statement  ->
                  Syn_Statement 
wrap_Statement sem (Inh_Statement _lhsIenv _lhsIinProducedEnv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIinProducedEnv _lhsIlib )
     in  (Syn_Statement _lhsOannotatedTree _lhsOenvUpdates _lhsOlibUpdates _lhsOoriginalTree ))
sem_Statement_AlterSequence :: Annotation ->
                               String ->
                               String ->
                               T_Statement 
sem_Statement_AlterSequence ann_ name_ ownedBy_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 9805 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 9810 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 9815 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  AlterSequence ann_ name_ ownedBy_
                  {-# LINE 9820 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  AlterSequence ann_ name_ ownedBy_
                  {-# LINE 9825 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 9830 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9835 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_AlterTable :: Annotation ->
                            String ->
                            ([AlterTableAction]) ->
                            T_Statement 
sem_Statement_AlterTable ann_ name_ actions_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 9853 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 9858 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  AlterTable ann_ name_ actions_
                  {-# LINE 9863 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  AlterTable ann_ name_ actions_
                  {-# LINE 9868 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 9873 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9878 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Assignment :: Annotation ->
                            String ->
                            T_Expression  ->
                            T_Statement 
sem_Statement_Assignment ann_ target_ value_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _valueOenv :: Environment
              _valueOlib :: LocalIdentifierBindings
              _valueIannotatedTree :: Expression
              _valueIliftedColumnName :: String
              _valueIoriginalTree :: Expression
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 9907 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 9912 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 9917 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 9922 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 23, column 9)
              _tpe =
                  {-# LINE 23 "./TypeChecking/Plpgsql.ag" #-}
                  do
                  let fromType = getTypeAnnotation _valueIannotatedTree
                  toType <- libLookupID _lhsIlib target_
                  dependsOnRTpe [getTypeAnnotation _valueIannotatedTree, toType] $ do
                  checkAssignmentValid _lhsIenv fromType toType
                  return $ Pseudo Void
                  {-# LINE 9932 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 30, column 9)
              _backTree =
                  {-# LINE 30 "./TypeChecking/Plpgsql.ag" #-}
                  Assignment ann_ target_ _valueIannotatedTree
                  {-# LINE 9937 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 31, column 9)
              _envUpdates =
                  {-# LINE 31 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 9942 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 32, column 9)
              _statementType =
                  {-# LINE 32 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 9947 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Assignment ann_ target_ _valueIannotatedTree
                  {-# LINE 9952 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Assignment ann_ target_ _valueIoriginalTree
                  {-# LINE 9957 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 9962 "AstInternal.hs" #-}
              -- copy rule (down)
              _valueOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 9967 "AstInternal.hs" #-}
              -- copy rule (down)
              _valueOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 9972 "AstInternal.hs" #-}
              ( _valueIannotatedTree,_valueIliftedColumnName,_valueIoriginalTree) =
                  (value_ _valueOenv _valueOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CaseStatement :: Annotation ->
                               T_Expression  ->
                               T_ExpressionListStatementListPairList  ->
                               T_StatementList  ->
                               T_Statement 
sem_Statement_CaseStatement ann_ val_ cases_ els_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _elsOenvUpdates :: ([EnvironmentUpdate])
              _elsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _valOenv :: Environment
              _valOlib :: LocalIdentifierBindings
              _casesOenv :: Environment
              _casesOlib :: LocalIdentifierBindings
              _elsOenv :: Environment
              _elsOlib :: LocalIdentifierBindings
              _valIannotatedTree :: Expression
              _valIliftedColumnName :: String
              _valIoriginalTree :: Expression
              _casesIannotatedTree :: ExpressionListStatementListPairList
              _casesIoriginalTree :: ExpressionListStatementListPairList
              _elsIannotatedTree :: StatementList
              _elsIoriginalTree :: StatementList
              _elsIproducedEnv :: Environment
              _elsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10010 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10015 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 106, column 9)
              _elsOenvUpdates =
                  {-# LINE 106 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10020 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 107, column 9)
              _elsOlibUpdates =
                  {-# LINE 107 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10025 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CaseStatement ann_ _valIannotatedTree _casesIannotatedTree _elsIannotatedTree
                  {-# LINE 10030 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CaseStatement ann_ _valIoriginalTree _casesIoriginalTree _elsIoriginalTree
                  {-# LINE 10035 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 10040 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10045 "AstInternal.hs" #-}
              -- copy rule (down)
              _valOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10050 "AstInternal.hs" #-}
              -- copy rule (down)
              _valOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10055 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10060 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10065 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10070 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10075 "AstInternal.hs" #-}
              ( _valIannotatedTree,_valIliftedColumnName,_valIoriginalTree) =
                  (val_ _valOenv _valOlib )
              ( _casesIannotatedTree,_casesIoriginalTree) =
                  (cases_ _casesOenv _casesOlib )
              ( _elsIannotatedTree,_elsIoriginalTree,_elsIproducedEnv,_elsIproducedLib) =
                  (els_ _elsOenv _elsOenvUpdates _elsOlib _elsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_ContinueStatement :: Annotation ->
                                   T_Statement 
sem_Statement_ContinueStatement ann_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10097 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10102 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ContinueStatement ann_
                  {-# LINE 10107 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ContinueStatement ann_
                  {-# LINE 10112 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 10117 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10122 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Copy :: Annotation ->
                      String ->
                      T_StringList  ->
                      T_CopySource  ->
                      T_Statement 
sem_Statement_Copy ann_ table_ targetCols_ source_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _targetColsOenv :: Environment
              _targetColsOlib :: LocalIdentifierBindings
              _sourceOenv :: Environment
              _sourceOlib :: LocalIdentifierBindings
              _targetColsIannotatedTree :: StringList
              _targetColsIoriginalTree :: StringList
              _targetColsIstrings :: ([String])
              _sourceIannotatedTree :: CopySource
              _sourceIoriginalTree :: CopySource
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10150 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10155 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Copy ann_ table_ _targetColsIannotatedTree _sourceIannotatedTree
                  {-# LINE 10160 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Copy ann_ table_ _targetColsIoriginalTree _sourceIoriginalTree
                  {-# LINE 10165 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 10170 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10175 "AstInternal.hs" #-}
              -- copy rule (down)
              _targetColsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10180 "AstInternal.hs" #-}
              -- copy rule (down)
              _targetColsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10185 "AstInternal.hs" #-}
              -- copy rule (down)
              _sourceOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10190 "AstInternal.hs" #-}
              -- copy rule (down)
              _sourceOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10195 "AstInternal.hs" #-}
              ( _targetColsIannotatedTree,_targetColsIoriginalTree,_targetColsIstrings) =
                  (targetCols_ _targetColsOenv _targetColsOlib )
              ( _sourceIannotatedTree,_sourceIoriginalTree) =
                  (source_ _sourceOenv _sourceOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CopyData :: Annotation ->
                          String ->
                          T_Statement 
sem_Statement_CopyData ann_ insData_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10216 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10221 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CopyData ann_ insData_
                  {-# LINE 10226 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CopyData ann_ insData_
                  {-# LINE 10231 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 10236 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10241 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateDomain :: Annotation ->
                              String ->
                              T_TypeName  ->
                              String ->
                              T_MaybeBoolExpression  ->
                              T_Statement 
sem_Statement_CreateDomain ann_ name_ typ_ checkName_ check_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _checkOlib :: LocalIdentifierBindings
              _lhsOoriginalTree :: Statement
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _checkOenv :: Environment
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              _checkIannotatedTree :: MaybeBoolExpression
              _checkIoriginalTree :: MaybeBoolExpression
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 10276 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 10281 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 10286 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10291 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 64, column 9)
              _tpe =
                  {-# LINE 64 "./TypeChecking/MiscCreates.ag" #-}
                  Right $ Pseudo Void
                  {-# LINE 10296 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 65, column 9)
              _backTree =
                  {-# LINE 65 "./TypeChecking/MiscCreates.ag" #-}
                  CreateDomain ann_ name_ _typIannotatedTree checkName_ _checkIannotatedTree
                  {-# LINE 10301 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 66, column 9)
              _statementType =
                  {-# LINE 66 "./TypeChecking/MiscCreates.ag" #-}
                  []
                  {-# LINE 10306 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 67, column 9)
              _envUpdates =
                  {-# LINE 67 "./TypeChecking/MiscCreates.ag" #-}
                  [EnvCreateDomain (DomainType name_) _typInamedType]
                  {-# LINE 10311 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 69, column 9)
              _checkOlib =
                  {-# LINE 69 "./TypeChecking/MiscCreates.ag" #-}
                  fromRight _lhsIlib $
                  updateBindings _lhsIlib _lhsIenv
                    [LibStackIDs [("", [("value", _typInamedType)])]]
                  {-# LINE 10318 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateDomain ann_ name_ _typIannotatedTree checkName_ _checkIannotatedTree
                  {-# LINE 10323 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateDomain ann_ name_ _typIoriginalTree checkName_ _checkIoriginalTree
                  {-# LINE 10328 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10333 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10338 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10343 "AstInternal.hs" #-}
              -- copy rule (down)
              _checkOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10348 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
              ( _checkIannotatedTree,_checkIoriginalTree) =
                  (check_ _checkOenv _checkOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateFunction :: Annotation ->
                                String ->
                                T_ParamDefList  ->
                                T_TypeName  ->
                                T_Language  ->
                                String ->
                                T_FnBody  ->
                                T_Volatility  ->
                                T_Statement 
sem_Statement_CreateFunction ann_ name_ params_ rettype_ lang_ bodyQuote_ body_ vol_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _bodyOenv :: Environment
              _bodyOlib :: LocalIdentifierBindings
              _lhsOoriginalTree :: Statement
              _paramsOenv :: Environment
              _paramsOlib :: LocalIdentifierBindings
              _rettypeOenv :: Environment
              _rettypeOlib :: LocalIdentifierBindings
              _langOenv :: Environment
              _langOlib :: LocalIdentifierBindings
              _volOenv :: Environment
              _volOlib :: LocalIdentifierBindings
              _paramsIannotatedTree :: ParamDefList
              _paramsIoriginalTree :: ParamDefList
              _paramsIparams :: ([(String, Type)])
              _rettypeIannotatedTree :: TypeName
              _rettypeInamedType :: Type
              _rettypeIoriginalTree :: TypeName
              _langIannotatedTree :: Language
              _langIoriginalTree :: Language
              _bodyIannotatedTree :: FnBody
              _bodyIoriginalTree :: FnBody
              _volIannotatedTree :: Volatility
              _volIoriginalTree :: Volatility
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 10403 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 10408 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 10413 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10418 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 23, column 9)
              _tpe =
                  {-# LINE 23 "./TypeChecking/CreateFunction.ag" #-}
                  dependsOnRTpe
                    (_rettypeInamedType : _parameterTypes    ) $
                    Right $ Pseudo Void
                  {-# LINE 10425 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 26, column 9)
              _envUpdates =
                  {-# LINE 26 "./TypeChecking/CreateFunction.ag" #-}
                  dependsOn [tpeToT _tpe    ] []
                            [EnvCreateFunction FunName
                                               (map toLower name_)
                                               _parameterTypes
                                               _rettypeInamedType
                                               False]
                  {-# LINE 10435 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 32, column 9)
              _parameterTypes =
                  {-# LINE 32 "./TypeChecking/CreateFunction.ag" #-}
                  (map snd _paramsIparams)
                  {-# LINE 10440 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 34, column 9)
              _backTree =
                  {-# LINE 34 "./TypeChecking/CreateFunction.ag" #-}
                  CreateFunction ann_
                                 name_
                                 _paramsIannotatedTree
                                 _rettypeIannotatedTree
                                 _langIannotatedTree
                                 bodyQuote_
                                 _bodyIannotatedTree
                                 _volIannotatedTree
                  {-# LINE 10452 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 42, column 9)
              _statementType =
                  {-# LINE 42 "./TypeChecking/CreateFunction.ag" #-}
                  []
                  {-# LINE 10457 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 43, column 9)
              _bodyOenv =
                  {-# LINE 43 "./TypeChecking/CreateFunction.ag" #-}
                  _lhsIinProducedEnv
                  {-# LINE 10462 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateFunction.ag"(line 99, column 9)
              _bodyOlib =
                  {-# LINE 99 "./TypeChecking/CreateFunction.ag" #-}
                  let p = _paramsIparams
                          ++ (zip posNames $ map snd _paramsIparams)
                  in fromRight _lhsIlib $
                     updateBindings _lhsIlib _lhsIenv
                                    [LibStackIDs [("", p)
                                                 ,(name_, _paramsIparams)]]
                  where
                    posNames :: [String]
                    posNames = map (\l -> '$':show l) [1..]
                  {-# LINE 10475 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateFunction ann_ name_ _paramsIannotatedTree _rettypeIannotatedTree _langIannotatedTree bodyQuote_ _bodyIannotatedTree _volIannotatedTree
                  {-# LINE 10480 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateFunction ann_ name_ _paramsIoriginalTree _rettypeIoriginalTree _langIoriginalTree bodyQuote_ _bodyIoriginalTree _volIoriginalTree
                  {-# LINE 10485 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10490 "AstInternal.hs" #-}
              -- copy rule (down)
              _paramsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10495 "AstInternal.hs" #-}
              -- copy rule (down)
              _paramsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10500 "AstInternal.hs" #-}
              -- copy rule (down)
              _rettypeOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10505 "AstInternal.hs" #-}
              -- copy rule (down)
              _rettypeOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10510 "AstInternal.hs" #-}
              -- copy rule (down)
              _langOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10515 "AstInternal.hs" #-}
              -- copy rule (down)
              _langOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10520 "AstInternal.hs" #-}
              -- copy rule (down)
              _volOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10525 "AstInternal.hs" #-}
              -- copy rule (down)
              _volOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10530 "AstInternal.hs" #-}
              ( _paramsIannotatedTree,_paramsIoriginalTree,_paramsIparams) =
                  (params_ _paramsOenv _paramsOlib )
              ( _rettypeIannotatedTree,_rettypeInamedType,_rettypeIoriginalTree) =
                  (rettype_ _rettypeOenv _rettypeOlib )
              ( _langIannotatedTree,_langIoriginalTree) =
                  (lang_ _langOenv _langOlib )
              ( _bodyIannotatedTree,_bodyIoriginalTree) =
                  (body_ _bodyOenv _bodyOlib )
              ( _volIannotatedTree,_volIoriginalTree) =
                  (vol_ _volOenv _volOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateLanguage :: Annotation ->
                                String ->
                                T_Statement 
sem_Statement_CreateLanguage ann_ name_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10557 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10562 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10567 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateLanguage ann_ name_
                  {-# LINE 10572 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateLanguage ann_ name_
                  {-# LINE 10577 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 10582 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10587 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateSequence :: Annotation ->
                                String ->
                                Integer ->
                                Integer ->
                                Integer ->
                                Integer ->
                                Integer ->
                                T_Statement 
sem_Statement_CreateSequence ann_ name_ incr_ min_ max_ start_ cache_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10609 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10614 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10619 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateSequence ann_ name_ incr_ min_ max_ start_ cache_
                  {-# LINE 10624 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateSequence ann_ name_ incr_ min_ max_ start_ cache_
                  {-# LINE 10629 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 10634 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10639 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateTable :: Annotation ->
                             String ->
                             T_AttributeDefList  ->
                             T_ConstraintList  ->
                             T_Statement 
sem_Statement_CreateTable ann_ name_ atts_ cons_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _attrTypes :: ([Type])
              _consOlib :: LocalIdentifierBindings
              _lhsOoriginalTree :: Statement
              _attsOenv :: Environment
              _attsOlib :: LocalIdentifierBindings
              _consOenv :: Environment
              _attsIannotatedTree :: AttributeDefList
              _attsIattrs :: ([(String, Type)])
              _attsIoriginalTree :: AttributeDefList
              _consIannotatedTree :: ConstraintList
              _consIoriginalTree :: ConstraintList
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 10674 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 10679 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 10684 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10689 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 25, column 9)
              _tpe =
                  {-# LINE 25 "./TypeChecking/CreateTable.ag" #-}
                  dependsOnRTpe _attrTypes     $ Right $ Pseudo Void
                  {-# LINE 10694 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 26, column 9)
              _envUpdates =
                  {-# LINE 26 "./TypeChecking/CreateTable.ag" #-}
                  dependsOn _attrTypes     []
                    [EnvCreateTable name_ _attsIattrs defaultSystemColumns]
                  {-# LINE 10700 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 29, column 9)
              _attrTypes =
                  {-# LINE 29 "./TypeChecking/CreateTable.ag" #-}
                  map snd _attsIattrs
                  {-# LINE 10705 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 31, column 9)
              _statementType =
                  {-# LINE 31 "./TypeChecking/CreateTable.ag" #-}
                  []
                  {-# LINE 10710 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 32, column 9)
              _backTree =
                  {-# LINE 32 "./TypeChecking/CreateTable.ag" #-}
                  CreateTable ann_
                              name_
                              _attsIannotatedTree
                              _consIannotatedTree
                  {-# LINE 10718 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 36, column 9)
              _consOlib =
                  {-# LINE 36 "./TypeChecking/CreateTable.ag" #-}
                  case updateBindings _lhsIlib _lhsIenv
                    [LibStackIDs [("", _attsIattrs)]] of
                     Left x -> error $ show x
                     Right e -> e
                  {-# LINE 10726 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateTable ann_ name_ _attsIannotatedTree _consIannotatedTree
                  {-# LINE 10731 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateTable ann_ name_ _attsIoriginalTree _consIoriginalTree
                  {-# LINE 10736 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10741 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10746 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10751 "AstInternal.hs" #-}
              -- copy rule (down)
              _consOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10756 "AstInternal.hs" #-}
              ( _attsIannotatedTree,_attsIattrs,_attsIoriginalTree) =
                  (atts_ _attsOenv _attsOlib )
              ( _consIannotatedTree,_consIoriginalTree) =
                  (cons_ _consOenv _consOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateTableAs :: Annotation ->
                               String ->
                               T_SelectExpression  ->
                               T_Statement 
sem_Statement_CreateTableAs ann_ name_ expr_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: SelectExpression
              _exprIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _exprIoriginalTree :: SelectExpression
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 10789 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 10794 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 10799 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10804 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 53, column 9)
              _tpe =
                  {-# LINE 53 "./TypeChecking/CreateTable.ag" #-}
                  dependsOnRTpe [_selType    ] $ do
                    _attrs
                    Right _selType
                  {-# LINE 10811 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 57, column 9)
              _envUpdates =
                  {-# LINE 57 "./TypeChecking/CreateTable.ag" #-}
                  leftToEmpty (\as -> [EnvCreateTable name_ as defaultSystemColumns]) $ do
                     ats <- _attrs
                     return $ dependsOn (tpeToT _tpe     :
                                         (map snd ats)) [] ats
                  {-# LINE 10819 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 63, column 9)
              _selType =
                  {-# LINE 63 "./TypeChecking/CreateTable.ag" #-}
                  getTypeAnnotation _exprIannotatedTree
                  {-# LINE 10824 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 65, column 9)
              _attrs =
                  {-# LINE 65 "./TypeChecking/CreateTable.ag" #-}
                  unwrapSetOfComposite _selType
                  {-# LINE 10829 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 67, column 9)
              _backTree =
                  {-# LINE 67 "./TypeChecking/CreateTable.ag" #-}
                  CreateTableAs ann_ name_ _exprIannotatedTree
                  {-# LINE 10834 "AstInternal.hs" #-}
              -- "./TypeChecking/CreateTable.ag"(line 68, column 9)
              _statementType =
                  {-# LINE 68 "./TypeChecking/CreateTable.ag" #-}
                  []
                  {-# LINE 10839 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateTableAs ann_ name_ _exprIannotatedTree
                  {-# LINE 10844 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateTableAs ann_ name_ _exprIoriginalTree
                  {-# LINE 10849 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10854 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10859 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10864 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIlibUpdates,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateTrigger :: Annotation ->
                               String ->
                               T_TriggerWhen  ->
                               ([TriggerEvent]) ->
                               String ->
                               T_TriggerFire  ->
                               String ->
                               ([Expression]) ->
                               T_Statement 
sem_Statement_CreateTrigger ann_ name_ wh_ events_ tbl_ firing_ fnName_ fnArgs_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _whOenv :: Environment
              _whOlib :: LocalIdentifierBindings
              _firingOenv :: Environment
              _firingOlib :: LocalIdentifierBindings
              _whIannotatedTree :: TriggerWhen
              _whIoriginalTree :: TriggerWhen
              _firingIannotatedTree :: TriggerFire
              _firingIoriginalTree :: TriggerFire
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10897 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10902 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateTrigger ann_ name_ _whIannotatedTree events_ tbl_ _firingIannotatedTree fnName_ fnArgs_
                  {-# LINE 10907 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateTrigger ann_ name_ _whIoriginalTree events_ tbl_ _firingIoriginalTree fnName_ fnArgs_
                  {-# LINE 10912 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 10917 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 10922 "AstInternal.hs" #-}
              -- copy rule (down)
              _whOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10927 "AstInternal.hs" #-}
              -- copy rule (down)
              _whOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10932 "AstInternal.hs" #-}
              -- copy rule (down)
              _firingOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 10937 "AstInternal.hs" #-}
              -- copy rule (down)
              _firingOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 10942 "AstInternal.hs" #-}
              ( _whIannotatedTree,_whIoriginalTree) =
                  (wh_ _whOenv _whOlib )
              ( _firingIannotatedTree,_firingIoriginalTree) =
                  (firing_ _firingOenv _firingOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateType :: Annotation ->
                            String ->
                            T_TypeAttributeDefList  ->
                            T_Statement 
sem_Statement_CreateType ann_ name_ atts_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _attsOenv :: Environment
              _attsOlib :: LocalIdentifierBindings
              _attsIannotatedTree :: TypeAttributeDefList
              _attsIattrs :: ([(String, Type)])
              _attsIoriginalTree :: TypeAttributeDefList
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 10975 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 10980 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 10985 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 10990 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 51, column 9)
              _tpe =
                  {-# LINE 51 "./TypeChecking/MiscCreates.ag" #-}
                  Right $ Pseudo Void
                  {-# LINE 10995 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 52, column 9)
              _backTree =
                  {-# LINE 52 "./TypeChecking/MiscCreates.ag" #-}
                  CreateType ann_ name_ _attsIannotatedTree
                  {-# LINE 11000 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 53, column 9)
              _statementType =
                  {-# LINE 53 "./TypeChecking/MiscCreates.ag" #-}
                  []
                  {-# LINE 11005 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 54, column 9)
              _envUpdates =
                  {-# LINE 54 "./TypeChecking/MiscCreates.ag" #-}
                  [EnvCreateComposite name_ _attsIattrs]
                  {-# LINE 11010 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateType ann_ name_ _attsIannotatedTree
                  {-# LINE 11015 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateType ann_ name_ _attsIoriginalTree
                  {-# LINE 11020 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11025 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11030 "AstInternal.hs" #-}
              -- copy rule (down)
              _attsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11035 "AstInternal.hs" #-}
              ( _attsIannotatedTree,_attsIattrs,_attsIoriginalTree) =
                  (atts_ _attsOenv _attsOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_CreateView :: Annotation ->
                            String ->
                            T_SelectExpression  ->
                            T_Statement 
sem_Statement_CreateView ann_ name_ expr_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: SelectExpression
              _exprIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _exprIoriginalTree :: SelectExpression
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 11066 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 11071 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 11076 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11081 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 15, column 9)
              _tpe =
                  {-# LINE 15 "./TypeChecking/MiscCreates.ag" #-}
                  dependsOnRTpe [getTypeAnnotation _exprIannotatedTree] $
                    Right $ Pseudo Void
                  {-# LINE 11087 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 17, column 9)
              _backTree =
                  {-# LINE 17 "./TypeChecking/MiscCreates.ag" #-}
                  CreateView ann_ name_ _exprIannotatedTree
                  {-# LINE 11092 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 18, column 9)
              _attrs =
                  {-# LINE 18 "./TypeChecking/MiscCreates.ag" #-}
                  case getTypeAnnotation _exprIannotatedTree of
                    SetOfType (CompositeType c) -> c
                    _ -> []
                  {-# LINE 11099 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 21, column 9)
              _envUpdates =
                  {-# LINE 21 "./TypeChecking/MiscCreates.ag" #-}
                  [EnvCreateView name_ _attrs    ]
                  {-# LINE 11104 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 22, column 9)
              _statementType =
                  {-# LINE 22 "./TypeChecking/MiscCreates.ag" #-}
                  []
                  {-# LINE 11109 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  CreateView ann_ name_ _exprIannotatedTree
                  {-# LINE 11114 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  CreateView ann_ name_ _exprIoriginalTree
                  {-# LINE 11119 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11124 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11129 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11134 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIlibUpdates,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Delete :: Annotation ->
                        String ->
                        T_MaybeBoolExpression  ->
                        T_MaybeSelectList  ->
                        T_Statement 
sem_Statement_Delete ann_ table_ whr_ returning_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _whrOlib :: LocalIdentifierBindings
              _returningOlib :: LocalIdentifierBindings
              _lhsOoriginalTree :: Statement
              _whrOenv :: Environment
              _returningOenv :: Environment
              _whrIannotatedTree :: MaybeBoolExpression
              _whrIoriginalTree :: MaybeBoolExpression
              _returningIannotatedTree :: MaybeSelectList
              _returningIlistType :: (Maybe [(String,Type)])
              _returningIoriginalTree :: MaybeSelectList
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 11170 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 11175 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 11180 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11185 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 153, column 9)
              _tpe =
                  {-# LINE 153 "./TypeChecking/Dml.ag" #-}
                  checkRelationExists _lhsIenv table_ >>
                  Right (Pseudo Void)
                  {-# LINE 11191 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 156, column 9)
              _statementType =
                  {-# LINE 156 "./TypeChecking/Dml.ag" #-}
                  [StatementType [] (fromMaybe [] _returningIlistType)]
                  {-# LINE 11196 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 158, column 9)
              _backTree =
                  {-# LINE 158 "./TypeChecking/Dml.ag" #-}
                  Delete ann_ table_ _whrIannotatedTree _returningIannotatedTree
                  {-# LINE 11201 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 159, column 9)
              _envUpdates =
                  {-# LINE 159 "./TypeChecking/Dml.ag" #-}
                  []
                  {-# LINE 11206 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 164, column 9)
              _lib =
                  {-# LINE 164 "./TypeChecking/Dml.ag" #-}
                  fromRight _lhsIlib $ do
                  columnTypes <- envCompositeAttrs _lhsIenv relationComposites table_
                  updateBindings _lhsIlib _lhsIenv [LibStackIDs [("", columnTypes)]]
                  {-# LINE 11213 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 168, column 9)
              _whrOlib =
                  {-# LINE 168 "./TypeChecking/Dml.ag" #-}
                  _lib
                  {-# LINE 11218 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 169, column 9)
              _returningOlib =
                  {-# LINE 169 "./TypeChecking/Dml.ag" #-}
                  _lib
                  {-# LINE 11223 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Delete ann_ table_ _whrIannotatedTree _returningIannotatedTree
                  {-# LINE 11228 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Delete ann_ table_ _whrIoriginalTree _returningIoriginalTree
                  {-# LINE 11233 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11238 "AstInternal.hs" #-}
              -- copy rule (down)
              _whrOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11243 "AstInternal.hs" #-}
              -- copy rule (down)
              _returningOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11248 "AstInternal.hs" #-}
              ( _whrIannotatedTree,_whrIoriginalTree) =
                  (whr_ _whrOenv _whrOlib )
              ( _returningIannotatedTree,_returningIlistType,_returningIoriginalTree) =
                  (returning_ _returningOenv _returningOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_DropFunction :: Annotation ->
                              T_IfExists  ->
                              T_StringTypeNameListPairList  ->
                              T_Cascade  ->
                              T_Statement 
sem_Statement_DropFunction ann_ ifE_ sigs_ cascade_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _ifEOenv :: Environment
              _ifEOlib :: LocalIdentifierBindings
              _sigsOenv :: Environment
              _sigsOlib :: LocalIdentifierBindings
              _cascadeOenv :: Environment
              _cascadeOlib :: LocalIdentifierBindings
              _ifEIannotatedTree :: IfExists
              _ifEIoriginalTree :: IfExists
              _sigsIannotatedTree :: StringTypeNameListPairList
              _sigsIfnSigs :: ([(String,[Type])])
              _sigsIoriginalTree :: StringTypeNameListPairList
              _cascadeIannotatedTree :: Cascade
              _cascadeIoriginalTree :: Cascade
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 11290 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 11295 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 11300 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11305 "AstInternal.hs" #-}
              -- "./TypeChecking/Drops.ag"(line 10, column 9)
              _tpe =
                  {-# LINE 10 "./TypeChecking/Drops.ag" #-}
                  Right $ Pseudo Void
                  {-# LINE 11310 "AstInternal.hs" #-}
              -- "./TypeChecking/Drops.ag"(line 11, column 9)
              _backTree =
                  {-# LINE 11 "./TypeChecking/Drops.ag" #-}
                  DropFunction ann_ _ifEIannotatedTree _sigsIannotatedTree _cascadeIannotatedTree
                  {-# LINE 11315 "AstInternal.hs" #-}
              -- "./TypeChecking/Drops.ag"(line 12, column 9)
              _envUpdates =
                  {-# LINE 12 "./TypeChecking/Drops.ag" #-}
                  flip map _sigsIfnSigs $ \(nm,args) ->
                        EnvDropFunction ifE nm args
                  where
                    ifE = _ifEIannotatedTree == IfExists
                  {-# LINE 11323 "AstInternal.hs" #-}
              -- "./TypeChecking/Drops.ag"(line 16, column 9)
              _statementType =
                  {-# LINE 16 "./TypeChecking/Drops.ag" #-}
                  []
                  {-# LINE 11328 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  DropFunction ann_ _ifEIannotatedTree _sigsIannotatedTree _cascadeIannotatedTree
                  {-# LINE 11333 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  DropFunction ann_ _ifEIoriginalTree _sigsIoriginalTree _cascadeIoriginalTree
                  {-# LINE 11338 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11343 "AstInternal.hs" #-}
              -- copy rule (down)
              _ifEOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11348 "AstInternal.hs" #-}
              -- copy rule (down)
              _ifEOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11353 "AstInternal.hs" #-}
              -- copy rule (down)
              _sigsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11358 "AstInternal.hs" #-}
              -- copy rule (down)
              _sigsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11363 "AstInternal.hs" #-}
              -- copy rule (down)
              _cascadeOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11368 "AstInternal.hs" #-}
              -- copy rule (down)
              _cascadeOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11373 "AstInternal.hs" #-}
              ( _ifEIannotatedTree,_ifEIoriginalTree) =
                  (ifE_ _ifEOenv _ifEOlib )
              ( _sigsIannotatedTree,_sigsIfnSigs,_sigsIoriginalTree) =
                  (sigs_ _sigsOenv _sigsOlib )
              ( _cascadeIannotatedTree,_cascadeIoriginalTree) =
                  (cascade_ _cascadeOenv _cascadeOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_DropSomething :: Annotation ->
                               T_DropType  ->
                               T_IfExists  ->
                               T_StringList  ->
                               T_Cascade  ->
                               T_Statement 
sem_Statement_DropSomething ann_ dropType_ ifE_ names_ cascade_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _dropTypeOenv :: Environment
              _dropTypeOlib :: LocalIdentifierBindings
              _ifEOenv :: Environment
              _ifEOlib :: LocalIdentifierBindings
              _namesOenv :: Environment
              _namesOlib :: LocalIdentifierBindings
              _cascadeOenv :: Environment
              _cascadeOlib :: LocalIdentifierBindings
              _dropTypeIannotatedTree :: DropType
              _dropTypeIoriginalTree :: DropType
              _ifEIannotatedTree :: IfExists
              _ifEIoriginalTree :: IfExists
              _namesIannotatedTree :: StringList
              _namesIoriginalTree :: StringList
              _namesIstrings :: ([String])
              _cascadeIannotatedTree :: Cascade
              _cascadeIoriginalTree :: Cascade
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11416 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11421 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  DropSomething ann_ _dropTypeIannotatedTree _ifEIannotatedTree _namesIannotatedTree _cascadeIannotatedTree
                  {-# LINE 11426 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  DropSomething ann_ _dropTypeIoriginalTree _ifEIoriginalTree _namesIoriginalTree _cascadeIoriginalTree
                  {-# LINE 11431 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 11436 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11441 "AstInternal.hs" #-}
              -- copy rule (down)
              _dropTypeOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11446 "AstInternal.hs" #-}
              -- copy rule (down)
              _dropTypeOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11451 "AstInternal.hs" #-}
              -- copy rule (down)
              _ifEOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11456 "AstInternal.hs" #-}
              -- copy rule (down)
              _ifEOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11461 "AstInternal.hs" #-}
              -- copy rule (down)
              _namesOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11466 "AstInternal.hs" #-}
              -- copy rule (down)
              _namesOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11471 "AstInternal.hs" #-}
              -- copy rule (down)
              _cascadeOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11476 "AstInternal.hs" #-}
              -- copy rule (down)
              _cascadeOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11481 "AstInternal.hs" #-}
              ( _dropTypeIannotatedTree,_dropTypeIoriginalTree) =
                  (dropType_ _dropTypeOenv _dropTypeOlib )
              ( _ifEIannotatedTree,_ifEIoriginalTree) =
                  (ifE_ _ifEOenv _ifEOlib )
              ( _namesIannotatedTree,_namesIoriginalTree,_namesIstrings) =
                  (names_ _namesOenv _namesOlib )
              ( _cascadeIannotatedTree,_cascadeIoriginalTree) =
                  (cascade_ _cascadeOenv _cascadeOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Execute :: Annotation ->
                         T_Expression  ->
                         T_Statement 
sem_Statement_Execute ann_ expr_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11511 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11516 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Execute ann_ _exprIannotatedTree
                  {-# LINE 11521 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Execute ann_ _exprIoriginalTree
                  {-# LINE 11526 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 11531 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11536 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11541 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11546 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_ExecuteInto :: Annotation ->
                             T_Expression  ->
                             T_StringList  ->
                             T_Statement 
sem_Statement_ExecuteInto ann_ expr_ targets_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _targetsOenv :: Environment
              _targetsOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              _targetsIannotatedTree :: StringList
              _targetsIoriginalTree :: StringList
              _targetsIstrings :: ([String])
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11576 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11581 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ExecuteInto ann_ _exprIannotatedTree _targetsIannotatedTree
                  {-# LINE 11586 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ExecuteInto ann_ _exprIoriginalTree _targetsIoriginalTree
                  {-# LINE 11591 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 11596 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11601 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11606 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11611 "AstInternal.hs" #-}
              -- copy rule (down)
              _targetsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11616 "AstInternal.hs" #-}
              -- copy rule (down)
              _targetsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11621 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
              ( _targetsIannotatedTree,_targetsIoriginalTree,_targetsIstrings) =
                  (targets_ _targetsOenv _targetsOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_ForIntegerStatement :: Annotation ->
                                     String ->
                                     T_Expression  ->
                                     T_Expression  ->
                                     T_StatementList  ->
                                     T_Statement 
sem_Statement_ForIntegerStatement ann_ var_ from_ to_ sts_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _stsOenvUpdates :: ([EnvironmentUpdate])
              _stsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _stsOlib :: LocalIdentifierBindings
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _fromOenv :: Environment
              _fromOlib :: LocalIdentifierBindings
              _toOenv :: Environment
              _toOlib :: LocalIdentifierBindings
              _stsOenv :: Environment
              _fromIannotatedTree :: Expression
              _fromIliftedColumnName :: String
              _fromIoriginalTree :: Expression
              _toIannotatedTree :: Expression
              _toIliftedColumnName :: String
              _toIoriginalTree :: Expression
              _stsIannotatedTree :: StatementList
              _stsIoriginalTree :: StatementList
              _stsIproducedEnv :: Environment
              _stsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 11669 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 11674 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 11679 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11684 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 110, column 9)
              _stsOenvUpdates =
                  {-# LINE 110 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11689 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 111, column 9)
              _stsOlibUpdates =
                  {-# LINE 111 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11694 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 36, column 9)
              _varTypeE =
                  {-# LINE 36 "./TypeChecking/Plpgsql.ag" #-}
                  libLookupID _lhsIlib var_
                  {-# LINE 11699 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 37, column 9)
              _tpe =
                  {-# LINE 37 "./TypeChecking/Plpgsql.ag" #-}
                  do
                  let fromType = getTypeAnnotation _fromIannotatedTree
                      toType = getTypeAnnotation _toIannotatedTree
                  dependsOnRTpe [fromType,toType] $ do
                  errorWhen (fromType /= toType) [FromToTypesNotSame fromType toType]
                  case _varTypeE     of
                    Right t -> checkAssignmentValid _lhsIenv fromType t
                    Left _ -> return ()
                  return $ Pseudo Void
                  {-# LINE 11712 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 48, column 9)
              _stsOlib =
                  {-# LINE 48 "./TypeChecking/Plpgsql.ag" #-}
                  case _varTypeE     of
                    Left [UnrecognisedIdentifier var_] ->
                        fromRight _lhsIlib $
                        updateBindings _lhsIlib _lhsIenv
                                       [LibStackIDs [("", [(var_,getTypeAnnotation _fromIannotatedTree)])]]
                    _ -> _lhsIlib
                  {-# LINE 11722 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 56, column 9)
              _backTree =
                  {-# LINE 56 "./TypeChecking/Plpgsql.ag" #-}
                  ForIntegerStatement ann_ var_ _fromIannotatedTree _toIannotatedTree _stsIannotatedTree
                  {-# LINE 11727 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 57, column 9)
              _envUpdates =
                  {-# LINE 57 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 11732 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 58, column 9)
              _statementType =
                  {-# LINE 58 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 11737 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ForIntegerStatement ann_ var_ _fromIannotatedTree _toIannotatedTree _stsIannotatedTree
                  {-# LINE 11742 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ForIntegerStatement ann_ var_ _fromIoriginalTree _toIoriginalTree _stsIoriginalTree
                  {-# LINE 11747 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11752 "AstInternal.hs" #-}
              -- copy rule (down)
              _fromOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11757 "AstInternal.hs" #-}
              -- copy rule (down)
              _fromOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11762 "AstInternal.hs" #-}
              -- copy rule (down)
              _toOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11767 "AstInternal.hs" #-}
              -- copy rule (down)
              _toOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11772 "AstInternal.hs" #-}
              -- copy rule (down)
              _stsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11777 "AstInternal.hs" #-}
              ( _fromIannotatedTree,_fromIliftedColumnName,_fromIoriginalTree) =
                  (from_ _fromOenv _fromOlib )
              ( _toIannotatedTree,_toIliftedColumnName,_toIoriginalTree) =
                  (to_ _toOenv _toOlib )
              ( _stsIannotatedTree,_stsIoriginalTree,_stsIproducedEnv,_stsIproducedLib) =
                  (sts_ _stsOenv _stsOenvUpdates _stsOlib _stsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_ForSelectStatement :: Annotation ->
                                    String ->
                                    T_SelectExpression  ->
                                    T_StatementList  ->
                                    T_Statement 
sem_Statement_ForSelectStatement ann_ var_ sel_ sts_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _stsOenvUpdates :: ([EnvironmentUpdate])
              _stsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _stsOlib :: LocalIdentifierBindings
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _selOenv :: Environment
              _selOlib :: LocalIdentifierBindings
              _stsOenv :: Environment
              _selIannotatedTree :: SelectExpression
              _selIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selIoriginalTree :: SelectExpression
              _stsIannotatedTree :: StatementList
              _stsIoriginalTree :: StatementList
              _stsIproducedEnv :: Environment
              _stsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 11821 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 11826 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 11831 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11836 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 110, column 9)
              _stsOenvUpdates =
                  {-# LINE 110 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11841 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 111, column 9)
              _stsOlibUpdates =
                  {-# LINE 111 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11846 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 63, column 9)
              _selType =
                  {-# LINE 63 "./TypeChecking/Plpgsql.ag" #-}
                  getTypeAnnotation _selIannotatedTree
                  {-# LINE 11851 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 64, column 9)
              _tpe =
                  {-# LINE 64 "./TypeChecking/Plpgsql.ag" #-}
                  do
                  dependsOnRTpe [_selType    ] $ do
                  toType <- libLookupID _lhsIlib var_
                  dependsOnRTpe [toType] $ do
                  checkAssignmentValid _lhsIenv _selType     toType
                  return $ Pseudo Void
                  {-# LINE 11861 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 75, column 9)
              _stsOlib =
                  {-# LINE 75 "./TypeChecking/Plpgsql.ag" #-}
                  if okToUpdate
                    then fromRight _lhsIlib $
                         updateBindings _lhsIlib _lhsIenv [LibStackIDs [("", [(var_,_selType    )])]]
                    else _lhsIlib
                  where
                    okToUpdate = isRight _tpe     && _selType     /= TypeCheckFailed
                  {-# LINE 11871 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 84, column 9)
              _backTree =
                  {-# LINE 84 "./TypeChecking/Plpgsql.ag" #-}
                  ForSelectStatement ann_ var_ _selIannotatedTree _stsIannotatedTree
                  {-# LINE 11876 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 85, column 9)
              _envUpdates =
                  {-# LINE 85 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 11881 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 86, column 9)
              _statementType =
                  {-# LINE 86 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 11886 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ForSelectStatement ann_ var_ _selIannotatedTree _stsIannotatedTree
                  {-# LINE 11891 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ForSelectStatement ann_ var_ _selIoriginalTree _stsIoriginalTree
                  {-# LINE 11896 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11901 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11906 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11911 "AstInternal.hs" #-}
              -- copy rule (down)
              _stsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11916 "AstInternal.hs" #-}
              ( _selIannotatedTree,_selIlibUpdates,_selIoriginalTree) =
                  (sel_ _selOenv _selOlib )
              ( _stsIannotatedTree,_stsIoriginalTree,_stsIproducedEnv,_stsIproducedLib) =
                  (sts_ _stsOenv _stsOenvUpdates _stsOlib _stsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_If :: Annotation ->
                    T_ExpressionStatementListPairList  ->
                    T_StatementList  ->
                    T_Statement 
sem_Statement_If ann_ cases_ els_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _elsOenvUpdates :: ([EnvironmentUpdate])
              _elsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _casesOenv :: Environment
              _casesOlib :: LocalIdentifierBindings
              _elsOenv :: Environment
              _elsOlib :: LocalIdentifierBindings
              _casesIannotatedTree :: ExpressionStatementListPairList
              _casesIoriginalTree :: ExpressionStatementListPairList
              _elsIannotatedTree :: StatementList
              _elsIoriginalTree :: StatementList
              _elsIproducedEnv :: Environment
              _elsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11950 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11955 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 106, column 9)
              _elsOenvUpdates =
                  {-# LINE 106 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11960 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 107, column 9)
              _elsOlibUpdates =
                  {-# LINE 107 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 11965 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  If ann_ _casesIannotatedTree _elsIannotatedTree
                  {-# LINE 11970 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  If ann_ _casesIoriginalTree _elsIoriginalTree
                  {-# LINE 11975 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 11980 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 11985 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 11990 "AstInternal.hs" #-}
              -- copy rule (down)
              _casesOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 11995 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12000 "AstInternal.hs" #-}
              -- copy rule (down)
              _elsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12005 "AstInternal.hs" #-}
              ( _casesIannotatedTree,_casesIoriginalTree) =
                  (cases_ _casesOenv _casesOlib )
              ( _elsIannotatedTree,_elsIoriginalTree,_elsIproducedEnv,_elsIproducedLib) =
                  (els_ _elsOenv _elsOenvUpdates _elsOlib _elsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Insert :: Annotation ->
                        String ->
                        T_StringList  ->
                        T_SelectExpression  ->
                        T_MaybeSelectList  ->
                        T_Statement 
sem_Statement_Insert ann_ table_ targetCols_ insData_ returning_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _returningOlib :: LocalIdentifierBindings
              _lhsOoriginalTree :: Statement
              _targetColsOenv :: Environment
              _targetColsOlib :: LocalIdentifierBindings
              _insDataOenv :: Environment
              _insDataOlib :: LocalIdentifierBindings
              _returningOenv :: Environment
              _targetColsIannotatedTree :: StringList
              _targetColsIoriginalTree :: StringList
              _targetColsIstrings :: ([String])
              _insDataIannotatedTree :: SelectExpression
              _insDataIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _insDataIoriginalTree :: SelectExpression
              _returningIannotatedTree :: MaybeSelectList
              _returningIlistType :: (Maybe [(String,Type)])
              _returningIoriginalTree :: MaybeSelectList
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 12050 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 12055 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 12060 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12065 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 18, column 9)
              _tpe =
                  {-# LINE 18 "./TypeChecking/Dml.ag" #-}
                  dependsOnRTpe [getTypeAnnotation _insDataIannotatedTree] $ do
                    _columnTypes
                    Right $ Pseudo Void
                  {-# LINE 12072 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 22, column 9)
              _statementType =
                  {-# LINE 22 "./TypeChecking/Dml.ag" #-}
                  leftToEmpty (\ct -> [StatementType (getPlaceholderTypes _insDataIannotatedTree) (fromMaybe [] _returningIlistType)]) _columnTypes
                  {-# LINE 12077 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 25, column 9)
              _columnTypes =
                  {-# LINE 25 "./TypeChecking/Dml.ag" #-}
                  do
                  tys <- unwrapSetOfComposite $
                         getTypeAnnotation _insDataIannotatedTree
                  checkColumnConsistency _lhsIenv
                                         table_
                                         _targetColsIstrings
                                         tys
                  {-# LINE 12088 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 34, column 9)
              _backTree =
                  {-# LINE 34 "./TypeChecking/Dml.ag" #-}
                  Insert ann_ table_ _targetColsIannotatedTree
                         _insDataIannotatedTree _returningIannotatedTree
                  {-# LINE 12094 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 36, column 9)
              _envUpdates =
                  {-# LINE 36 "./TypeChecking/Dml.ag" #-}
                  []
                  {-# LINE 12099 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 42, column 9)
              _returningOlib =
                  {-# LINE 42 "./TypeChecking/Dml.ag" #-}
                  fromRight _lhsIlib $ do
                    atts <- envCompositeAttrs _lhsIenv relationComposites table_
                    updateBindings _lhsIlib _lhsIenv [LibStackIDs [("", atts)]]
                  {-# LINE 12106 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Insert ann_ table_ _targetColsIannotatedTree _insDataIannotatedTree _returningIannotatedTree
                  {-# LINE 12111 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Insert ann_ table_ _targetColsIoriginalTree _insDataIoriginalTree _returningIoriginalTree
                  {-# LINE 12116 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12121 "AstInternal.hs" #-}
              -- copy rule (down)
              _targetColsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12126 "AstInternal.hs" #-}
              -- copy rule (down)
              _targetColsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12131 "AstInternal.hs" #-}
              -- copy rule (down)
              _insDataOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12136 "AstInternal.hs" #-}
              -- copy rule (down)
              _insDataOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12141 "AstInternal.hs" #-}
              -- copy rule (down)
              _returningOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12146 "AstInternal.hs" #-}
              ( _targetColsIannotatedTree,_targetColsIoriginalTree,_targetColsIstrings) =
                  (targetCols_ _targetColsOenv _targetColsOlib )
              ( _insDataIannotatedTree,_insDataIlibUpdates,_insDataIoriginalTree) =
                  (insData_ _insDataOenv _insDataOlib )
              ( _returningIannotatedTree,_returningIlistType,_returningIoriginalTree) =
                  (returning_ _returningOenv _returningOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Notify :: Annotation ->
                        String ->
                        T_Statement 
sem_Statement_Notify ann_ name_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12169 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12174 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12179 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Notify ann_ name_
                  {-# LINE 12184 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Notify ann_ name_
                  {-# LINE 12189 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12194 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12199 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_NullStatement :: Annotation ->
                               T_Statement 
sem_Statement_NullStatement ann_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12215 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12220 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  NullStatement ann_
                  {-# LINE 12225 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  NullStatement ann_
                  {-# LINE 12230 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12235 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12240 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Perform :: Annotation ->
                         T_Expression  ->
                         T_Statement 
sem_Statement_Perform ann_ expr_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12262 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12267 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Perform ann_ _exprIannotatedTree
                  {-# LINE 12272 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Perform ann_ _exprIoriginalTree
                  {-# LINE 12277 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12282 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12287 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12292 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12297 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Raise :: Annotation ->
                       T_RaiseType  ->
                       String ->
                       T_ExpressionList  ->
                       T_Statement 
sem_Statement_Raise ann_ level_ message_ args_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _levelOenv :: Environment
              _levelOlib :: LocalIdentifierBindings
              _argsOenv :: Environment
              _argsOlib :: LocalIdentifierBindings
              _levelIannotatedTree :: RaiseType
              _levelIoriginalTree :: RaiseType
              _argsIannotatedTree :: ExpressionList
              _argsIoriginalTree :: ExpressionList
              _argsItypeList :: ([Type])
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12327 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12332 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Raise ann_ _levelIannotatedTree message_ _argsIannotatedTree
                  {-# LINE 12337 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Raise ann_ _levelIoriginalTree message_ _argsIoriginalTree
                  {-# LINE 12342 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12347 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12352 "AstInternal.hs" #-}
              -- copy rule (down)
              _levelOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12357 "AstInternal.hs" #-}
              -- copy rule (down)
              _levelOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12362 "AstInternal.hs" #-}
              -- copy rule (down)
              _argsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12367 "AstInternal.hs" #-}
              -- copy rule (down)
              _argsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12372 "AstInternal.hs" #-}
              ( _levelIannotatedTree,_levelIoriginalTree) =
                  (level_ _levelOenv _levelOlib )
              ( _argsIannotatedTree,_argsIoriginalTree,_argsItypeList) =
                  (args_ _argsOenv _argsOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Return :: Annotation ->
                        T_MaybeExpression  ->
                        T_Statement 
sem_Statement_Return ann_ value_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _valueOenv :: Environment
              _valueOlib :: LocalIdentifierBindings
              _valueIannotatedTree :: MaybeExpression
              _valueIoriginalTree :: MaybeExpression
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 12403 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 12408 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 12413 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12418 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 12, column 9)
              _tpe =
                  {-# LINE 12 "./TypeChecking/Plpgsql.ag" #-}
                  dependsOnRTpe [maybe typeBool
                                      getTypeAnnotation
                                      _valueIannotatedTree] $ Right $ Pseudo Void
                  {-# LINE 12425 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 16, column 9)
              _backTree =
                  {-# LINE 16 "./TypeChecking/Plpgsql.ag" #-}
                  Return ann_ _valueIannotatedTree
                  {-# LINE 12430 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 17, column 9)
              _envUpdates =
                  {-# LINE 17 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 12435 "AstInternal.hs" #-}
              -- "./TypeChecking/Plpgsql.ag"(line 18, column 9)
              _statementType =
                  {-# LINE 18 "./TypeChecking/Plpgsql.ag" #-}
                  []
                  {-# LINE 12440 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Return ann_ _valueIannotatedTree
                  {-# LINE 12445 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Return ann_ _valueIoriginalTree
                  {-# LINE 12450 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12455 "AstInternal.hs" #-}
              -- copy rule (down)
              _valueOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12460 "AstInternal.hs" #-}
              -- copy rule (down)
              _valueOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12465 "AstInternal.hs" #-}
              ( _valueIannotatedTree,_valueIoriginalTree) =
                  (value_ _valueOenv _valueOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_ReturnNext :: Annotation ->
                            T_Expression  ->
                            T_Statement 
sem_Statement_ReturnNext ann_ expr_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12489 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12494 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ReturnNext ann_ _exprIannotatedTree
                  {-# LINE 12499 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ReturnNext ann_ _exprIoriginalTree
                  {-# LINE 12504 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12509 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12514 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12519 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12524 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_ReturnQuery :: Annotation ->
                             T_SelectExpression  ->
                             T_Statement 
sem_Statement_ReturnQuery ann_ sel_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _selOenv :: Environment
              _selOlib :: LocalIdentifierBindings
              _selIannotatedTree :: SelectExpression
              _selIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selIoriginalTree :: SelectExpression
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12548 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12553 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ReturnQuery ann_ _selIannotatedTree
                  {-# LINE 12558 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ReturnQuery ann_ _selIoriginalTree
                  {-# LINE 12563 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12568 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12573 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12578 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12583 "AstInternal.hs" #-}
              ( _selIannotatedTree,_selIlibUpdates,_selIoriginalTree) =
                  (sel_ _selOenv _selOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_SelectStatement :: Annotation ->
                                 T_SelectExpression  ->
                                 T_Statement 
sem_Statement_SelectStatement ann_ ex_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _lhsOoriginalTree :: Statement
              _exOenv :: Environment
              _exOlib :: LocalIdentifierBindings
              _exIannotatedTree :: SelectExpression
              _exIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _exIoriginalTree :: SelectExpression
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 12613 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 12618 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 12623 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 14, column 9)
              _tpe =
                  {-# LINE 14 "./TypeChecking/SelectStatement.ag" #-}
                  dependsOnRTpe [getTypeAnnotation _exIannotatedTree] $ Right $ Pseudo Void
                  {-# LINE 12628 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 15, column 9)
              _statementType =
                  {-# LINE 15 "./TypeChecking/SelectStatement.ag" #-}
                  [StatementType (getPlaceholderTypes _exIannotatedTree) $ leftToEmpty id  $
                                      unwrapSetOfComposite $
                                      getTypeAnnotation _exIannotatedTree]
                  {-# LINE 12635 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 18, column 9)
              _backTree =
                  {-# LINE 18 "./TypeChecking/SelectStatement.ag" #-}
                  SelectStatement ann_ _exIannotatedTree
                  {-# LINE 12640 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectStatement.ag"(line 19, column 9)
              _envUpdates =
                  {-# LINE 19 "./TypeChecking/SelectStatement.ag" #-}
                  []
                  {-# LINE 12645 "AstInternal.hs" #-}
              -- "./TypeChecking/SelectLists.ag"(line 79, column 9)
              _libUpdates =
                  {-# LINE 79 "./TypeChecking/SelectLists.ag" #-}
                  _exIlibUpdates
                  {-# LINE 12650 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SelectStatement ann_ _exIannotatedTree
                  {-# LINE 12655 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SelectStatement ann_ _exIoriginalTree
                  {-# LINE 12660 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12665 "AstInternal.hs" #-}
              -- copy rule (down)
              _exOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12670 "AstInternal.hs" #-}
              -- copy rule (down)
              _exOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12675 "AstInternal.hs" #-}
              ( _exIannotatedTree,_exIlibUpdates,_exIoriginalTree) =
                  (ex_ _exOenv _exOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Set :: Annotation ->
                     String ->
                     ([SetValue]) ->
                     T_Statement 
sem_Statement_Set ann_ name_ values_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12695 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12700 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12705 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Set ann_ name_ values_
                  {-# LINE 12710 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Set ann_ name_ values_
                  {-# LINE 12715 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12720 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12725 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Truncate :: Annotation ->
                          T_StringList  ->
                          T_RestartIdentity  ->
                          T_Cascade  ->
                          T_Statement 
sem_Statement_Truncate ann_ tables_ restartIdentity_ cascade_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _tablesOenv :: Environment
              _tablesOlib :: LocalIdentifierBindings
              _restartIdentityOenv :: Environment
              _restartIdentityOlib :: LocalIdentifierBindings
              _cascadeOenv :: Environment
              _cascadeOlib :: LocalIdentifierBindings
              _tablesIannotatedTree :: StringList
              _tablesIoriginalTree :: StringList
              _tablesIstrings :: ([String])
              _restartIdentityIannotatedTree :: RestartIdentity
              _restartIdentityIoriginalTree :: RestartIdentity
              _cascadeIannotatedTree :: Cascade
              _cascadeIoriginalTree :: Cascade
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12757 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12762 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Truncate ann_ _tablesIannotatedTree _restartIdentityIannotatedTree _cascadeIannotatedTree
                  {-# LINE 12767 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Truncate ann_ _tablesIoriginalTree _restartIdentityIoriginalTree _cascadeIoriginalTree
                  {-# LINE 12772 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 12777 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12782 "AstInternal.hs" #-}
              -- copy rule (down)
              _tablesOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12787 "AstInternal.hs" #-}
              -- copy rule (down)
              _tablesOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12792 "AstInternal.hs" #-}
              -- copy rule (down)
              _restartIdentityOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12797 "AstInternal.hs" #-}
              -- copy rule (down)
              _restartIdentityOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12802 "AstInternal.hs" #-}
              -- copy rule (down)
              _cascadeOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12807 "AstInternal.hs" #-}
              -- copy rule (down)
              _cascadeOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 12812 "AstInternal.hs" #-}
              ( _tablesIannotatedTree,_tablesIoriginalTree,_tablesIstrings) =
                  (tables_ _tablesOenv _tablesOlib )
              ( _restartIdentityIannotatedTree,_restartIdentityIoriginalTree) =
                  (restartIdentity_ _restartIdentityOenv _restartIdentityOlib )
              ( _cascadeIannotatedTree,_cascadeIoriginalTree) =
                  (cascade_ _cascadeOenv _cascadeOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_Update :: Annotation ->
                        String ->
                        T_SetClauseList  ->
                        T_MaybeBoolExpression  ->
                        T_MaybeSelectList  ->
                        T_Statement 
sem_Statement_Update ann_ table_ assigns_ whr_ returning_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Statement
              _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tpe :: (Either [TypeError] Type)
              _envUpdates :: ([EnvironmentUpdate])
              _whrOlib :: LocalIdentifierBindings
              _assignsOlib :: LocalIdentifierBindings
              _returningOlib :: LocalIdentifierBindings
              _lhsOoriginalTree :: Statement
              _assignsOenv :: Environment
              _whrOenv :: Environment
              _returningOenv :: Environment
              _assignsIannotatedTree :: SetClauseList
              _assignsIoriginalTree :: SetClauseList
              _assignsIpairs :: ([(String,Type)])
              _assignsIrowSetErrors :: ([TypeError])
              _whrIannotatedTree :: MaybeBoolExpression
              _whrIoriginalTree :: MaybeBoolExpression
              _returningIannotatedTree :: MaybeSelectList
              _returningIlistType :: (Maybe [(String,Type)])
              _returningIoriginalTree :: MaybeSelectList
              -- "./TypeChecking/Statements.ag"(line 61, column 9)
              _lhsOannotatedTree =
                  {-# LINE 61 "./TypeChecking/Statements.ag" #-}
                  annTypesAndErrors _backTree
                    (tpeToT _tpe    )
                    (getErrors _tpe    )
                    $ Just (map StatementTypeA _statementType     ++
                            [EnvUpdates _envUpdates    ])
                  {-# LINE 12859 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 67, column 9)
              _lhsOenvUpdates =
                  {-# LINE 67 "./TypeChecking/Statements.ag" #-}
                  _envUpdates
                  {-# LINE 12864 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 68, column 9)
              _lhsOlibUpdates =
                  {-# LINE 68 "./TypeChecking/Statements.ag" #-}
                  _libUpdates
                  {-# LINE 12869 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 73, column 9)
              _libUpdates =
                  {-# LINE 73 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 12874 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 58, column 9)
              _tpe =
                  {-# LINE 58 "./TypeChecking/Dml.ag" #-}
                  do
                  checkRelationExists _lhsIenv table_
                  dependsOnRTpe (map snd _assignsIpairs) $ do
                    _columnTypes
                    liftErrors _assignsIrowSetErrors
                    return $ Pseudo Void
                  {-# LINE 12884 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 65, column 9)
              _statementType =
                  {-# LINE 65 "./TypeChecking/Dml.ag" #-}
                  leftToEmpty (\ct -> [StatementType [] (fromMaybe [] _returningIlistType)]) _columnTypes
                  {-# LINE 12889 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 68, column 9)
              _columnTypes =
                  {-# LINE 68 "./TypeChecking/Dml.ag" #-}
                  checkColumnConsistency _lhsIenv
                                         table_
                                         (map fst _assignsIpairs)
                                         _assignsIpairs
                  {-# LINE 12897 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 74, column 9)
              _backTree =
                  {-# LINE 74 "./TypeChecking/Dml.ag" #-}
                  Update ann_
                         table_
                         _assignsIannotatedTree
                         _whrIannotatedTree
                         _returningIannotatedTree
                  {-# LINE 12906 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 79, column 9)
              _envUpdates =
                  {-# LINE 79 "./TypeChecking/Dml.ag" #-}
                  []
                  {-# LINE 12911 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 87, column 9)
              _lib =
                  {-# LINE 87 "./TypeChecking/Dml.ag" #-}
                  fromRight _lhsIlib $ do
                  ct <- envCompositeAttrs _lhsIenv
                                          relationComposites
                                          table_
                  updateBindings _lhsIlib _lhsIenv [LibStackIDs [("", ct)]]
                  {-# LINE 12920 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 93, column 9)
              _whrOlib =
                  {-# LINE 93 "./TypeChecking/Dml.ag" #-}
                  _lib
                  {-# LINE 12925 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 94, column 9)
              _assignsOlib =
                  {-# LINE 94 "./TypeChecking/Dml.ag" #-}
                  _lib
                  {-# LINE 12930 "AstInternal.hs" #-}
              -- "./TypeChecking/Dml.ag"(line 95, column 9)
              _returningOlib =
                  {-# LINE 95 "./TypeChecking/Dml.ag" #-}
                  _lib
                  {-# LINE 12935 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Update ann_ table_ _assignsIannotatedTree _whrIannotatedTree _returningIannotatedTree
                  {-# LINE 12940 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Update ann_ table_ _assignsIoriginalTree _whrIoriginalTree _returningIoriginalTree
                  {-# LINE 12945 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 12950 "AstInternal.hs" #-}
              -- copy rule (down)
              _assignsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12955 "AstInternal.hs" #-}
              -- copy rule (down)
              _whrOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12960 "AstInternal.hs" #-}
              -- copy rule (down)
              _returningOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 12965 "AstInternal.hs" #-}
              ( _assignsIannotatedTree,_assignsIoriginalTree,_assignsIpairs,_assignsIrowSetErrors) =
                  (assigns_ _assignsOenv _assignsOlib )
              ( _whrIannotatedTree,_whrIoriginalTree) =
                  (whr_ _whrOenv _whrOlib )
              ( _returningIannotatedTree,_returningIlistType,_returningIoriginalTree) =
                  (returning_ _returningOenv _returningOlib )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_Statement_WhileStatement :: Annotation ->
                                T_Expression  ->
                                T_StatementList  ->
                                T_Statement 
sem_Statement_WhileStatement ann_ expr_ sts_  =
    (\ _lhsIenv
       _lhsIinProducedEnv
       _lhsIlib ->
         (let _lhsOenvUpdates :: ([EnvironmentUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _stsOenvUpdates :: ([EnvironmentUpdate])
              _stsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: Statement
              _lhsOoriginalTree :: Statement
              _exprOenv :: Environment
              _exprOlib :: LocalIdentifierBindings
              _stsOenv :: Environment
              _stsOlib :: LocalIdentifierBindings
              _exprIannotatedTree :: Expression
              _exprIliftedColumnName :: String
              _exprIoriginalTree :: Expression
              _stsIannotatedTree :: StatementList
              _stsIoriginalTree :: StatementList
              _stsIproducedEnv :: Environment
              _stsIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 89, column 9)
              _lhsOenvUpdates =
                  {-# LINE 89 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 13002 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 90, column 9)
              _lhsOlibUpdates =
                  {-# LINE 90 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 13007 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 110, column 9)
              _stsOenvUpdates =
                  {-# LINE 110 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 13012 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 111, column 9)
              _stsOlibUpdates =
                  {-# LINE 111 "./TypeChecking/Statements.ag" #-}
                  []
                  {-# LINE 13017 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  WhileStatement ann_ _exprIannotatedTree _stsIannotatedTree
                  {-# LINE 13022 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  WhileStatement ann_ _exprIoriginalTree _stsIoriginalTree
                  {-# LINE 13027 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13032 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13037 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 13042 "AstInternal.hs" #-}
              -- copy rule (down)
              _exprOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 13047 "AstInternal.hs" #-}
              -- copy rule (down)
              _stsOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 13052 "AstInternal.hs" #-}
              -- copy rule (down)
              _stsOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 13057 "AstInternal.hs" #-}
              ( _exprIannotatedTree,_exprIliftedColumnName,_exprIoriginalTree) =
                  (expr_ _exprOenv _exprOlib )
              ( _stsIannotatedTree,_stsIoriginalTree,_stsIproducedEnv,_stsIproducedLib) =
                  (sts_ _stsOenv _stsOenvUpdates _stsOlib _stsOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOenvUpdates,_lhsOlibUpdates,_lhsOoriginalTree)))
-- StatementList -----------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         envUpdates           : [EnvironmentUpdate]
         lib                  : LocalIdentifierBindings
         libUpdates           : [LocalIdentifierBindingsUpdate]
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         producedEnv          : Environment
         producedLib          : LocalIdentifierBindings
   alternatives:
      alternative Cons:
         child hd             : Statement 
         child tl             : StatementList 
         visit 0:
            local newEnv      : _
            local newLib      : _
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local newEnv      : _
            local newLib      : _
            local annotatedTree : _
            local originalTree : _
-}
type StatementList  = [(Statement)]
-- cata
sem_StatementList :: StatementList  ->
                     T_StatementList 
sem_StatementList list  =
    (Prelude.foldr sem_StatementList_Cons sem_StatementList_Nil (Prelude.map sem_Statement list) )
-- semantic domain
type T_StatementList  = Environment ->
                        ([EnvironmentUpdate]) ->
                        LocalIdentifierBindings ->
                        ([LocalIdentifierBindingsUpdate]) ->
                        ( StatementList,StatementList,Environment,LocalIdentifierBindings)
data Inh_StatementList  = Inh_StatementList {env_Inh_StatementList :: Environment,envUpdates_Inh_StatementList :: [EnvironmentUpdate],lib_Inh_StatementList :: LocalIdentifierBindings,libUpdates_Inh_StatementList :: [LocalIdentifierBindingsUpdate]}
data Syn_StatementList  = Syn_StatementList {annotatedTree_Syn_StatementList :: StatementList,originalTree_Syn_StatementList :: StatementList,producedEnv_Syn_StatementList :: Environment,producedLib_Syn_StatementList :: LocalIdentifierBindings}
wrap_StatementList :: T_StatementList  ->
                      Inh_StatementList  ->
                      Syn_StatementList 
wrap_StatementList sem (Inh_StatementList _lhsIenv _lhsIenvUpdates _lhsIlib _lhsIlibUpdates )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOproducedEnv,_lhsOproducedLib) =
             (sem _lhsIenv _lhsIenvUpdates _lhsIlib _lhsIlibUpdates )
     in  (Syn_StatementList _lhsOannotatedTree _lhsOoriginalTree _lhsOproducedEnv _lhsOproducedLib ))
sem_StatementList_Cons :: T_Statement  ->
                          T_StatementList  ->
                          T_StatementList 
sem_StatementList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIenvUpdates
       _lhsIlib
       _lhsIlibUpdates ->
         (let _hdOenv :: Environment
              _tlOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOlib :: LocalIdentifierBindings
              _lhsOproducedEnv :: Environment
              _lhsOproducedLib :: LocalIdentifierBindings
              _tlOenvUpdates :: ([EnvironmentUpdate])
              _tlOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _hdOinProducedEnv :: Environment
              _lhsOannotatedTree :: StatementList
              _lhsOoriginalTree :: StatementList
              _hdIannotatedTree :: Statement
              _hdIenvUpdates :: ([EnvironmentUpdate])
              _hdIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _hdIoriginalTree :: Statement
              _tlIannotatedTree :: StatementList
              _tlIoriginalTree :: StatementList
              _tlIproducedEnv :: Environment
              _tlIproducedLib :: LocalIdentifierBindings
              -- "./TypeChecking/Statements.ag"(line 36, column 9)
              _newEnv =
                  {-# LINE 36 "./TypeChecking/Statements.ag" #-}
                  fromRight _lhsIenv $ updateEnvironment _lhsIenv _lhsIenvUpdates
                  {-# LINE 13144 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 37, column 9)
              _newLib =
                  {-# LINE 37 "./TypeChecking/Statements.ag" #-}
                  fromRight _lhsIlib $ updateBindings _lhsIlib _lhsIenv _lhsIlibUpdates
                  {-# LINE 13149 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 39, column 9)
              _hdOenv =
                  {-# LINE 39 "./TypeChecking/Statements.ag" #-}
                  _newEnv
                  {-# LINE 13154 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 40, column 9)
              _tlOenv =
                  {-# LINE 40 "./TypeChecking/Statements.ag" #-}
                  _newEnv
                  {-# LINE 13159 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 41, column 9)
              _hdOlib =
                  {-# LINE 41 "./TypeChecking/Statements.ag" #-}
                  _newLib
                  {-# LINE 13164 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 42, column 9)
              _tlOlib =
                  {-# LINE 42 "./TypeChecking/Statements.ag" #-}
                  _newLib
                  {-# LINE 13169 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 46, column 9)
              _lhsOproducedEnv =
                  {-# LINE 46 "./TypeChecking/Statements.ag" #-}
                  _tlIproducedEnv
                  {-# LINE 13174 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 47, column 9)
              _lhsOproducedLib =
                  {-# LINE 47 "./TypeChecking/Statements.ag" #-}
                  _tlIproducedLib
                  {-# LINE 13179 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 50, column 9)
              _tlOenvUpdates =
                  {-# LINE 50 "./TypeChecking/Statements.ag" #-}
                  _hdIenvUpdates
                  {-# LINE 13184 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 51, column 9)
              _tlOlibUpdates =
                  {-# LINE 51 "./TypeChecking/Statements.ag" #-}
                  _hdIlibUpdates
                  {-# LINE 13189 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 76, column 12)
              _hdOinProducedEnv =
                  {-# LINE 76 "./TypeChecking/Statements.ag" #-}
                  _tlIproducedEnv
                  {-# LINE 13194 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 13199 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 13204 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13209 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13214 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIenvUpdates,_hdIlibUpdates,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOinProducedEnv _hdOlib )
              ( _tlIannotatedTree,_tlIoriginalTree,_tlIproducedEnv,_tlIproducedLib) =
                  (tl_ _tlOenv _tlOenvUpdates _tlOlib _tlOlibUpdates )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOproducedEnv,_lhsOproducedLib)))
sem_StatementList_Nil :: T_StatementList 
sem_StatementList_Nil  =
    (\ _lhsIenv
       _lhsIenvUpdates
       _lhsIlib
       _lhsIlibUpdates ->
         (let _lhsOproducedEnv :: Environment
              _lhsOproducedLib :: LocalIdentifierBindings
              _lhsOannotatedTree :: StatementList
              _lhsOoriginalTree :: StatementList
              -- "./TypeChecking/Statements.ag"(line 36, column 9)
              _newEnv =
                  {-# LINE 36 "./TypeChecking/Statements.ag" #-}
                  fromRight _lhsIenv $ updateEnvironment _lhsIenv _lhsIenvUpdates
                  {-# LINE 13234 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 37, column 9)
              _newLib =
                  {-# LINE 37 "./TypeChecking/Statements.ag" #-}
                  fromRight _lhsIlib $ updateBindings _lhsIlib _lhsIenv _lhsIlibUpdates
                  {-# LINE 13239 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 53, column 9)
              _lhsOproducedEnv =
                  {-# LINE 53 "./TypeChecking/Statements.ag" #-}
                  _newEnv
                  {-# LINE 13244 "AstInternal.hs" #-}
              -- "./TypeChecking/Statements.ag"(line 54, column 9)
              _lhsOproducedLib =
                  {-# LINE 54 "./TypeChecking/Statements.ag" #-}
                  _newLib
                  {-# LINE 13249 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 13254 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 13259 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13264 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13269 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOproducedEnv,_lhsOproducedLib)))
-- StringList --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
         strings              : [String]
   alternatives:
      alternative Cons:
         child hd             : {String}
         child tl             : StringList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type StringList  = [(String)]
-- cata
sem_StringList :: StringList  ->
                  T_StringList 
sem_StringList list  =
    (Prelude.foldr sem_StringList_Cons sem_StringList_Nil list )
-- semantic domain
type T_StringList  = Environment ->
                     LocalIdentifierBindings ->
                     ( StringList,StringList,([String]))
data Inh_StringList  = Inh_StringList {env_Inh_StringList :: Environment,lib_Inh_StringList :: LocalIdentifierBindings}
data Syn_StringList  = Syn_StringList {annotatedTree_Syn_StringList :: StringList,originalTree_Syn_StringList :: StringList,strings_Syn_StringList :: [String]}
wrap_StringList :: T_StringList  ->
                   Inh_StringList  ->
                   Syn_StringList 
wrap_StringList sem (Inh_StringList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOstrings) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_StringList _lhsOannotatedTree _lhsOoriginalTree _lhsOstrings ))
sem_StringList_Cons :: String ->
                       T_StringList  ->
                       T_StringList 
sem_StringList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOstrings :: ([String])
              _lhsOannotatedTree :: StringList
              _lhsOoriginalTree :: StringList
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _tlIannotatedTree :: StringList
              _tlIoriginalTree :: StringList
              _tlIstrings :: ([String])
              -- "./TypeChecking/Misc.ag"(line 67, column 10)
              _lhsOstrings =
                  {-# LINE 67 "./TypeChecking/Misc.ag" #-}
                  hd_ : _tlIstrings
                  {-# LINE 13330 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) hd_ _tlIannotatedTree
                  {-# LINE 13335 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) hd_ _tlIoriginalTree
                  {-# LINE 13340 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13345 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13350 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 13355 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 13360 "AstInternal.hs" #-}
              ( _tlIannotatedTree,_tlIoriginalTree,_tlIstrings) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOstrings)))
sem_StringList_Nil :: T_StringList 
sem_StringList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOstrings :: ([String])
              _lhsOannotatedTree :: StringList
              _lhsOoriginalTree :: StringList
              -- "./TypeChecking/Misc.ag"(line 68, column 9)
              _lhsOstrings =
                  {-# LINE 68 "./TypeChecking/Misc.ag" #-}
                  []
                  {-# LINE 13375 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 13380 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 13385 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13390 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13395 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree,_lhsOstrings)))
-- StringTypeNameListPair --------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         fnSig                : (String,[Type])
         originalTree         : SELF 
   alternatives:
      alternative Tuple:
         child x1             : {String}
         child x2             : TypeNameList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type StringTypeNameListPair  = ( (String),(TypeNameList))
-- cata
sem_StringTypeNameListPair :: StringTypeNameListPair  ->
                              T_StringTypeNameListPair 
sem_StringTypeNameListPair ( x1,x2)  =
    (sem_StringTypeNameListPair_Tuple x1 (sem_TypeNameList x2 ) )
-- semantic domain
type T_StringTypeNameListPair  = Environment ->
                                 LocalIdentifierBindings ->
                                 ( StringTypeNameListPair,((String,[Type])),StringTypeNameListPair)
data Inh_StringTypeNameListPair  = Inh_StringTypeNameListPair {env_Inh_StringTypeNameListPair :: Environment,lib_Inh_StringTypeNameListPair :: LocalIdentifierBindings}
data Syn_StringTypeNameListPair  = Syn_StringTypeNameListPair {annotatedTree_Syn_StringTypeNameListPair :: StringTypeNameListPair,fnSig_Syn_StringTypeNameListPair :: (String,[Type]),originalTree_Syn_StringTypeNameListPair :: StringTypeNameListPair}
wrap_StringTypeNameListPair :: T_StringTypeNameListPair  ->
                               Inh_StringTypeNameListPair  ->
                               Syn_StringTypeNameListPair 
wrap_StringTypeNameListPair sem (Inh_StringTypeNameListPair _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOfnSig,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_StringTypeNameListPair _lhsOannotatedTree _lhsOfnSig _lhsOoriginalTree ))
sem_StringTypeNameListPair_Tuple :: String ->
                                    T_TypeNameList  ->
                                    T_StringTypeNameListPair 
sem_StringTypeNameListPair_Tuple x1_ x2_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOfnSig :: ((String,[Type]))
              _lhsOannotatedTree :: StringTypeNameListPair
              _lhsOoriginalTree :: StringTypeNameListPair
              _x2Oenv :: Environment
              _x2Olib :: LocalIdentifierBindings
              _x2IannotatedTree :: TypeNameList
              _x2InamedTypes :: ([Type])
              _x2IoriginalTree :: TypeNameList
              -- "./TypeChecking/Drops.ag"(line 25, column 13)
              _lhsOfnSig =
                  {-# LINE 25 "./TypeChecking/Drops.ag" #-}
                  (x1_, _x2InamedTypes)
                  {-# LINE 13452 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (x1_,_x2IannotatedTree)
                  {-# LINE 13457 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (x1_,_x2IoriginalTree)
                  {-# LINE 13462 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13467 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13472 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 13477 "AstInternal.hs" #-}
              -- copy rule (down)
              _x2Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 13482 "AstInternal.hs" #-}
              ( _x2IannotatedTree,_x2InamedTypes,_x2IoriginalTree) =
                  (x2_ _x2Oenv _x2Olib )
          in  ( _lhsOannotatedTree,_lhsOfnSig,_lhsOoriginalTree)))
-- StringTypeNameListPairList ----------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         fnSigs               : [(String,[Type])]
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : StringTypeNameListPair 
         child tl             : StringTypeNameListPairList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type StringTypeNameListPairList  = [(StringTypeNameListPair)]
-- cata
sem_StringTypeNameListPairList :: StringTypeNameListPairList  ->
                                  T_StringTypeNameListPairList 
sem_StringTypeNameListPairList list  =
    (Prelude.foldr sem_StringTypeNameListPairList_Cons sem_StringTypeNameListPairList_Nil (Prelude.map sem_StringTypeNameListPair list) )
-- semantic domain
type T_StringTypeNameListPairList  = Environment ->
                                     LocalIdentifierBindings ->
                                     ( StringTypeNameListPairList,([(String,[Type])]),StringTypeNameListPairList)
data Inh_StringTypeNameListPairList  = Inh_StringTypeNameListPairList {env_Inh_StringTypeNameListPairList :: Environment,lib_Inh_StringTypeNameListPairList :: LocalIdentifierBindings}
data Syn_StringTypeNameListPairList  = Syn_StringTypeNameListPairList {annotatedTree_Syn_StringTypeNameListPairList :: StringTypeNameListPairList,fnSigs_Syn_StringTypeNameListPairList :: [(String,[Type])],originalTree_Syn_StringTypeNameListPairList :: StringTypeNameListPairList}
wrap_StringTypeNameListPairList :: T_StringTypeNameListPairList  ->
                                   Inh_StringTypeNameListPairList  ->
                                   Syn_StringTypeNameListPairList 
wrap_StringTypeNameListPairList sem (Inh_StringTypeNameListPairList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOfnSigs,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_StringTypeNameListPairList _lhsOannotatedTree _lhsOfnSigs _lhsOoriginalTree ))
sem_StringTypeNameListPairList_Cons :: T_StringTypeNameListPair  ->
                                       T_StringTypeNameListPairList  ->
                                       T_StringTypeNameListPairList 
sem_StringTypeNameListPairList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOfnSigs :: ([(String,[Type])])
              _lhsOannotatedTree :: StringTypeNameListPairList
              _lhsOoriginalTree :: StringTypeNameListPairList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: StringTypeNameListPair
              _hdIfnSig :: ((String,[Type]))
              _hdIoriginalTree :: StringTypeNameListPair
              _tlIannotatedTree :: StringTypeNameListPairList
              _tlIfnSigs :: ([(String,[Type])])
              _tlIoriginalTree :: StringTypeNameListPairList
              -- "./TypeChecking/Drops.ag"(line 20, column 12)
              _lhsOfnSigs =
                  {-# LINE 20 "./TypeChecking/Drops.ag" #-}
                  _hdIfnSig : _tlIfnSigs
                  {-# LINE 13550 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 13555 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 13560 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13565 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13570 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 13575 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 13580 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 13585 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 13590 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIfnSig,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIfnSigs,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOfnSigs,_lhsOoriginalTree)))
sem_StringTypeNameListPairList_Nil :: T_StringTypeNameListPairList 
sem_StringTypeNameListPairList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOfnSigs :: ([(String,[Type])])
              _lhsOannotatedTree :: StringTypeNameListPairList
              _lhsOoriginalTree :: StringTypeNameListPairList
              -- "./TypeChecking/Drops.ag"(line 21, column 11)
              _lhsOfnSigs =
                  {-# LINE 21 "./TypeChecking/Drops.ag" #-}
                  []
                  {-# LINE 13607 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 13612 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 13617 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13622 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13627 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOfnSigs,_lhsOoriginalTree)))
-- TableAlias --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative FullAlias:
         child alias          : {String}
         child cols           : {[String]}
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative NoAlias:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative TableAlias:
         child alias          : {String}
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data TableAlias  = FullAlias (String) ([String]) 
                 | NoAlias 
                 | TableAlias (String) 
                 deriving ( Data,Eq,Show,Typeable)
-- cata
sem_TableAlias :: TableAlias  ->
                  T_TableAlias 
sem_TableAlias (FullAlias _alias _cols )  =
    (sem_TableAlias_FullAlias _alias _cols )
sem_TableAlias (NoAlias )  =
    (sem_TableAlias_NoAlias )
sem_TableAlias (TableAlias _alias )  =
    (sem_TableAlias_TableAlias _alias )
-- semantic domain
type T_TableAlias  = Environment ->
                     LocalIdentifierBindings ->
                     ( TableAlias,TableAlias)
data Inh_TableAlias  = Inh_TableAlias {env_Inh_TableAlias :: Environment,lib_Inh_TableAlias :: LocalIdentifierBindings}
data Syn_TableAlias  = Syn_TableAlias {annotatedTree_Syn_TableAlias :: TableAlias,originalTree_Syn_TableAlias :: TableAlias}
wrap_TableAlias :: T_TableAlias  ->
                   Inh_TableAlias  ->
                   Syn_TableAlias 
wrap_TableAlias sem (Inh_TableAlias _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TableAlias _lhsOannotatedTree _lhsOoriginalTree ))
sem_TableAlias_FullAlias :: String ->
                            ([String]) ->
                            T_TableAlias 
sem_TableAlias_FullAlias alias_ cols_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TableAlias
              _lhsOoriginalTree :: TableAlias
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  FullAlias alias_ cols_
                  {-# LINE 13693 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  FullAlias alias_ cols_
                  {-# LINE 13698 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13703 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13708 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_TableAlias_NoAlias :: T_TableAlias 
sem_TableAlias_NoAlias  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TableAlias
              _lhsOoriginalTree :: TableAlias
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  NoAlias
                  {-# LINE 13720 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  NoAlias
                  {-# LINE 13725 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13730 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13735 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_TableAlias_TableAlias :: String ->
                             T_TableAlias 
sem_TableAlias_TableAlias alias_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TableAlias
              _lhsOoriginalTree :: TableAlias
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TableAlias alias_
                  {-# LINE 13748 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TableAlias alias_
                  {-# LINE 13753 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 13758 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 13763 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- TableRef ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         jlibUpdates          : [LocalIdentifierBindingsUpdate]
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         idLookups            : [(String,Type)]
         libUpdates           : [LocalIdentifierBindingsUpdate]
         originalTree         : SELF 
         qidLookups           : [(String,[(String,Type)])]
         qstarExpansion       : [(String,[(String,Type)])]
         starExpansion        : [(String,Type)]
   alternatives:
      alternative JoinedTref:
         child ann            : {Annotation}
         child tbl            : TableRef 
         child nat            : Natural 
         child joinType       : JoinType 
         child tbl1           : TableRef 
         child onExpr         : OnExpr 
         child alias          : TableAlias 
         visit 0:
            local libUpdates  : _
            local errs        : _
            local removeJoinAttrs : _
            local ejoinAttrs  : {Either [TypeError] [(String,Type)]}
            local joinNames   : _
            local joinAttrs   : _
            local idLookups   : {[(String,Type)]}
            local qidLookups  : {[(String,[(String,Type)])]}
            local starExpansion : {[(String,Type)]}
            local qstarExpansion : {[(String,[(String,Type)])]}
            local newLib      : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative SubTref:
         child ann            : {Annotation}
         child sel            : SelectExpression 
         child alias          : TableAlias 
         visit 0:
            local libUpdates  : _
            local errs        : _
            local selectAttrs : {Either [TypeError] [(String,Type)]}
            local idLookups   : {[(String,Type)]}
            local qidLookups  : {[(String,[(String,Type)])]}
            local starExpansion : {[(String,Type)]}
            local qstarExpansion : {[(String,[(String,Type)])]}
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative Tref:
         child ann            : {Annotation}
         child tbl            : {String}
         child alias          : TableAlias 
         visit 0:
            local libUpdates  : _
            local errs        : _
            local relType     : {Either [TypeError] ([(String, Type)], [(String, Type)])}
            local relType1    : _
            local pAttrs      : _
            local sAttrs      : _
            local idLookups   : {[(String,Type)]}
            local alias       : _
            local qidLookups  : {[(String,[(String,Type)])]}
            local starExpansion : {[(String,Type)]}
            local qstarExpansion : {[(String,[(String,Type)])]}
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative TrefFun:
         child ann            : {Annotation}
         child fn             : Expression 
         child alias          : TableAlias 
         visit 0:
            local libUpdates  : _
            local errs        : _
            local eqfunIdens  : {Either [TypeError] (String,[(String,Type)])}
            local qfunIdens   : _
            local alias2      : _
            local funIdens    : _
            local alias       : _
            local idLookups   : {[(String,Type)]}
            local qidLookups  : {[(String,[(String,Type)])]}
            local starExpansion : {[(String,Type)]}
            local qstarExpansion : {[(String,[(String,Type)])]}
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
-}
data TableRef  = JoinedTref (Annotation) (TableRef) (Natural) (JoinType) (TableRef) (OnExpr) (TableAlias) 
               | SubTref (Annotation) (SelectExpression) (TableAlias) 
               | Tref (Annotation) (String) (TableAlias) 
               | TrefFun (Annotation) (Expression) (TableAlias) 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_TableRef :: TableRef  ->
                T_TableRef 
sem_TableRef (JoinedTref _ann _tbl _nat _joinType _tbl1 _onExpr _alias )  =
    (sem_TableRef_JoinedTref _ann (sem_TableRef _tbl ) (sem_Natural _nat ) (sem_JoinType _joinType ) (sem_TableRef _tbl1 ) (sem_OnExpr _onExpr ) (sem_TableAlias _alias ) )
sem_TableRef (SubTref _ann _sel _alias )  =
    (sem_TableRef_SubTref _ann (sem_SelectExpression _sel ) (sem_TableAlias _alias ) )
sem_TableRef (Tref _ann _tbl _alias )  =
    (sem_TableRef_Tref _ann _tbl (sem_TableAlias _alias ) )
sem_TableRef (TrefFun _ann _fn _alias )  =
    (sem_TableRef_TrefFun _ann (sem_Expression _fn ) (sem_TableAlias _alias ) )
-- semantic domain
type T_TableRef  = Environment ->
                   ([LocalIdentifierBindingsUpdate]) ->
                   LocalIdentifierBindings ->
                   ( TableRef,([(String,Type)]),([LocalIdentifierBindingsUpdate]),TableRef,([(String,[(String,Type)])]),([(String,[(String,Type)])]),([(String,Type)]))
data Inh_TableRef  = Inh_TableRef {env_Inh_TableRef :: Environment,jlibUpdates_Inh_TableRef :: [LocalIdentifierBindingsUpdate],lib_Inh_TableRef :: LocalIdentifierBindings}
data Syn_TableRef  = Syn_TableRef {annotatedTree_Syn_TableRef :: TableRef,idLookups_Syn_TableRef :: [(String,Type)],libUpdates_Syn_TableRef :: [LocalIdentifierBindingsUpdate],originalTree_Syn_TableRef :: TableRef,qidLookups_Syn_TableRef :: [(String,[(String,Type)])],qstarExpansion_Syn_TableRef :: [(String,[(String,Type)])],starExpansion_Syn_TableRef :: [(String,Type)]}
wrap_TableRef :: T_TableRef  ->
                 Inh_TableRef  ->
                 Syn_TableRef 
wrap_TableRef sem (Inh_TableRef _lhsIenv _lhsIjlibUpdates _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOidLookups,_lhsOlibUpdates,_lhsOoriginalTree,_lhsOqidLookups,_lhsOqstarExpansion,_lhsOstarExpansion) =
             (sem _lhsIenv _lhsIjlibUpdates _lhsIlib )
     in  (Syn_TableRef _lhsOannotatedTree _lhsOidLookups _lhsOlibUpdates _lhsOoriginalTree _lhsOqidLookups _lhsOqstarExpansion _lhsOstarExpansion ))
sem_TableRef_JoinedTref :: Annotation ->
                           T_TableRef  ->
                           T_Natural  ->
                           T_JoinType  ->
                           T_TableRef  ->
                           T_OnExpr  ->
                           T_TableAlias  ->
                           T_TableRef 
sem_TableRef_JoinedTref ann_ tbl_ nat_ joinType_ tbl1_ onExpr_ alias_  =
    (\ _lhsIenv
       _lhsIjlibUpdates
       _lhsIlib ->
         (let _lhsOannotatedTree :: TableRef
              _ejoinAttrs :: (Either [TypeError] [(String,Type)])
              _idLookups :: ([(String,Type)])
              _qidLookups :: ([(String,[(String,Type)])])
              _starExpansion :: ([(String,Type)])
              _qstarExpansion :: ([(String,[(String,Type)])])
              _onExprOlib :: LocalIdentifierBindings
              _tblOjlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tbl1OjlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOidLookups :: ([(String,Type)])
              _lhsOqidLookups :: ([(String,[(String,Type)])])
              _lhsOstarExpansion :: ([(String,Type)])
              _lhsOqstarExpansion :: ([(String,[(String,Type)])])
              _lhsOoriginalTree :: TableRef
              _tblOenv :: Environment
              _tblOlib :: LocalIdentifierBindings
              _natOenv :: Environment
              _natOlib :: LocalIdentifierBindings
              _joinTypeOenv :: Environment
              _joinTypeOlib :: LocalIdentifierBindings
              _tbl1Oenv :: Environment
              _tbl1Olib :: LocalIdentifierBindings
              _onExprOenv :: Environment
              _aliasOenv :: Environment
              _aliasOlib :: LocalIdentifierBindings
              _tblIannotatedTree :: TableRef
              _tblIidLookups :: ([(String,Type)])
              _tblIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tblIoriginalTree :: TableRef
              _tblIqidLookups :: ([(String,[(String,Type)])])
              _tblIqstarExpansion :: ([(String,[(String,Type)])])
              _tblIstarExpansion :: ([(String,Type)])
              _natIannotatedTree :: Natural
              _natIoriginalTree :: Natural
              _joinTypeIannotatedTree :: JoinType
              _joinTypeIoriginalTree :: JoinType
              _tbl1IannotatedTree :: TableRef
              _tbl1IidLookups :: ([(String,Type)])
              _tbl1IlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tbl1IoriginalTree :: TableRef
              _tbl1IqidLookups :: ([(String,[(String,Type)])])
              _tbl1IqstarExpansion :: ([(String,[(String,Type)])])
              _tbl1IstarExpansion :: ([(String,Type)])
              _onExprIannotatedTree :: OnExpr
              _onExprIoriginalTree :: OnExpr
              _aliasIannotatedTree :: TableAlias
              _aliasIoriginalTree :: TableAlias
              -- "./TypeChecking/TableRefs.ag"(line 33, column 9)
              _lhsOannotatedTree =
                  {-# LINE 33 "./TypeChecking/TableRefs.ag" #-}
                  updateAnnotation (map TypeErrorA _errs     ++) _backTree
                  {-# LINE 13952 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 75, column 9)
              _libUpdates =
                  {-# LINE 75 "./TypeChecking/TableRefs.ag" #-}
                  if null _errs
                    then [LibStackIDs $ ("", _idLookups    ): _qidLookups
                         ,LibSetStarExpansion $ ("", _starExpansion    ): _qstarExpansion    ]
                    else []
                  {-# LINE 13960 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 135, column 9)
              _errs =
                  {-# LINE 135 "./TypeChecking/TableRefs.ag" #-}
                  fromLeft [] _ejoinAttrs
                  {-# LINE 13965 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 136, column 9)
              _removeJoinAttrs =
                  {-# LINE 136 "./TypeChecking/TableRefs.ag" #-}
                  filter (\(n,_) -> n `notElem` _joinNames    )
                  {-# LINE 13970 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 146, column 9)
              _ejoinAttrs =
                  {-# LINE 146 "./TypeChecking/TableRefs.ag" #-}
                  do
                  let jns = case (_natIannotatedTree, _onExprIoriginalTree) of
                                (Natural, _) -> commonFieldNames
                                (_,Just (JoinUsing _ s)) -> s
                                _ -> []
                      tjtsm = map (flip lookup _tblIidLookups) jns
                      t1jtsm = map (flip lookup _tbl1IidLookups) jns
                  errorWhen (not $ null $ filter (==Nothing) $ tjtsm ++ t1jtsm)
                            [MissingJoinAttribute]
                  let tjts = catMaybes tjtsm
                      t1jts = catMaybes t1jtsm
                      resolvedTypes :: [Either [TypeError] Type]
                      resolvedTypes = map (\(a,b) -> resolveResultSetType _lhsIenv [a,b]) $ zip tjts t1jts
                  liftErrors $ concat $ lefts resolvedTypes
                  return $ zip jns $ rights resolvedTypes
                  where
                    commonFieldNames = intersect (f _tblIstarExpansion) (f _tbl1IstarExpansion)
                                       where f = map fst
                  {-# LINE 13992 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 170, column 9)
              _joinNames =
                  {-# LINE 170 "./TypeChecking/TableRefs.ag" #-}
                  map fst _joinAttrs
                  {-# LINE 13997 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 171, column 9)
              _joinAttrs =
                  {-# LINE 171 "./TypeChecking/TableRefs.ag" #-}
                  fromRight [] _ejoinAttrs
                  {-# LINE 14002 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 176, column 9)
              _idLookups =
                  {-# LINE 176 "./TypeChecking/TableRefs.ag" #-}
                  _joinAttrs     ++
                    _removeJoinAttrs     _tblIidLookups ++
                    _removeJoinAttrs     _tbl1IidLookups
                  {-# LINE 14009 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 179, column 9)
              _qidLookups =
                  {-# LINE 179 "./TypeChecking/TableRefs.ag" #-}
                  _tblIqidLookups ++ _tbl1IqidLookups
                  {-# LINE 14014 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 180, column 9)
              _starExpansion =
                  {-# LINE 180 "./TypeChecking/TableRefs.ag" #-}
                  _joinAttrs     ++
                    _removeJoinAttrs     _tblIstarExpansion ++
                    _removeJoinAttrs     _tbl1IstarExpansion
                  {-# LINE 14021 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 183, column 9)
              _qstarExpansion =
                  {-# LINE 183 "./TypeChecking/TableRefs.ag" #-}
                  _tblIqstarExpansion ++ _tbl1IqstarExpansion
                  {-# LINE 14026 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 187, column 9)
              _newLib =
                  {-# LINE 187 "./TypeChecking/TableRefs.ag" #-}
                  case updateBindings _lhsIlib _lhsIenv (_libUpdates     ++ _lhsIjlibUpdates) of
                    Left x -> error $ show x
                    Right e ->                                      e
                  {-# LINE 14033 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 190, column 9)
              _onExprOlib =
                  {-# LINE 190 "./TypeChecking/TableRefs.ag" #-}
                  _newLib
                  {-# LINE 14038 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 192, column 9)
              _tblOjlibUpdates =
                  {-# LINE 192 "./TypeChecking/TableRefs.ag" #-}
                  _libUpdates
                  {-# LINE 14043 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 193, column 9)
              _tbl1OjlibUpdates =
                  {-# LINE 193 "./TypeChecking/TableRefs.ag" #-}
                  _libUpdates
                  {-# LINE 14048 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 248, column 9)
              _lhsOlibUpdates =
                  {-# LINE 248 "./TypeChecking/TableRefs.ag" #-}
                  _libUpdates
                  {-# LINE 14053 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 249, column 9)
              _lhsOidLookups =
                  {-# LINE 249 "./TypeChecking/TableRefs.ag" #-}
                  _idLookups
                  {-# LINE 14058 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 250, column 9)
              _lhsOqidLookups =
                  {-# LINE 250 "./TypeChecking/TableRefs.ag" #-}
                  _qidLookups
                  {-# LINE 14063 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 251, column 9)
              _lhsOstarExpansion =
                  {-# LINE 251 "./TypeChecking/TableRefs.ag" #-}
                  _starExpansion
                  {-# LINE 14068 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 252, column 9)
              _lhsOqstarExpansion =
                  {-# LINE 252 "./TypeChecking/TableRefs.ag" #-}
                  _qstarExpansion
                  {-# LINE 14073 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 264, column 9)
              _backTree =
                  {-# LINE 264 "./TypeChecking/TableRefs.ag" #-}
                  JoinedTref ann_
                             _tblIannotatedTree
                             _natIannotatedTree
                             _joinTypeIannotatedTree
                             _tbl1IannotatedTree
                             _onExprIannotatedTree
                             _aliasIannotatedTree
                  {-# LINE 14084 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  JoinedTref ann_ _tblIannotatedTree _natIannotatedTree _joinTypeIannotatedTree _tbl1IannotatedTree _onExprIannotatedTree _aliasIannotatedTree
                  {-# LINE 14089 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  JoinedTref ann_ _tblIoriginalTree _natIoriginalTree _joinTypeIoriginalTree _tbl1IoriginalTree _onExprIoriginalTree _aliasIoriginalTree
                  {-# LINE 14094 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14099 "AstInternal.hs" #-}
              -- copy rule (down)
              _tblOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14104 "AstInternal.hs" #-}
              -- copy rule (down)
              _tblOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14109 "AstInternal.hs" #-}
              -- copy rule (down)
              _natOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14114 "AstInternal.hs" #-}
              -- copy rule (down)
              _natOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14119 "AstInternal.hs" #-}
              -- copy rule (down)
              _joinTypeOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14124 "AstInternal.hs" #-}
              -- copy rule (down)
              _joinTypeOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14129 "AstInternal.hs" #-}
              -- copy rule (down)
              _tbl1Oenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14134 "AstInternal.hs" #-}
              -- copy rule (down)
              _tbl1Olib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14139 "AstInternal.hs" #-}
              -- copy rule (down)
              _onExprOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14144 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14149 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14154 "AstInternal.hs" #-}
              ( _tblIannotatedTree,_tblIidLookups,_tblIlibUpdates,_tblIoriginalTree,_tblIqidLookups,_tblIqstarExpansion,_tblIstarExpansion) =
                  (tbl_ _tblOenv _tblOjlibUpdates _tblOlib )
              ( _natIannotatedTree,_natIoriginalTree) =
                  (nat_ _natOenv _natOlib )
              ( _joinTypeIannotatedTree,_joinTypeIoriginalTree) =
                  (joinType_ _joinTypeOenv _joinTypeOlib )
              ( _tbl1IannotatedTree,_tbl1IidLookups,_tbl1IlibUpdates,_tbl1IoriginalTree,_tbl1IqidLookups,_tbl1IqstarExpansion,_tbl1IstarExpansion) =
                  (tbl1_ _tbl1Oenv _tbl1OjlibUpdates _tbl1Olib )
              ( _onExprIannotatedTree,_onExprIoriginalTree) =
                  (onExpr_ _onExprOenv _onExprOlib )
              ( _aliasIannotatedTree,_aliasIoriginalTree) =
                  (alias_ _aliasOenv _aliasOlib )
          in  ( _lhsOannotatedTree,_lhsOidLookups,_lhsOlibUpdates,_lhsOoriginalTree,_lhsOqidLookups,_lhsOqstarExpansion,_lhsOstarExpansion)))
sem_TableRef_SubTref :: Annotation ->
                        T_SelectExpression  ->
                        T_TableAlias  ->
                        T_TableRef 
sem_TableRef_SubTref ann_ sel_ alias_  =
    (\ _lhsIenv
       _lhsIjlibUpdates
       _lhsIlib ->
         (let _lhsOannotatedTree :: TableRef
              _selectAttrs :: (Either [TypeError] [(String,Type)])
              _idLookups :: ([(String,Type)])
              _qidLookups :: ([(String,[(String,Type)])])
              _starExpansion :: ([(String,Type)])
              _qstarExpansion :: ([(String,[(String,Type)])])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOidLookups :: ([(String,Type)])
              _lhsOqidLookups :: ([(String,[(String,Type)])])
              _lhsOstarExpansion :: ([(String,Type)])
              _lhsOqstarExpansion :: ([(String,[(String,Type)])])
              _lhsOoriginalTree :: TableRef
              _selOenv :: Environment
              _selOlib :: LocalIdentifierBindings
              _aliasOenv :: Environment
              _aliasOlib :: LocalIdentifierBindings
              _selIannotatedTree :: SelectExpression
              _selIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _selIoriginalTree :: SelectExpression
              _aliasIannotatedTree :: TableAlias
              _aliasIoriginalTree :: TableAlias
              -- "./TypeChecking/TableRefs.ag"(line 33, column 9)
              _lhsOannotatedTree =
                  {-# LINE 33 "./TypeChecking/TableRefs.ag" #-}
                  updateAnnotation (map TypeErrorA _errs     ++) _backTree
                  {-# LINE 14201 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 75, column 9)
              _libUpdates =
                  {-# LINE 75 "./TypeChecking/TableRefs.ag" #-}
                  if null _errs
                    then [LibStackIDs $ ("", _idLookups    ): _qidLookups
                         ,LibSetStarExpansion $ ("", _starExpansion    ): _qstarExpansion    ]
                    else []
                  {-# LINE 14209 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 92, column 9)
              _errs =
                  {-# LINE 92 "./TypeChecking/TableRefs.ag" #-}
                  case _selectAttrs     of
                          Left e -> e
                          Right _ -> []
                  {-# LINE 14216 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 96, column 9)
              _selectAttrs =
                  {-# LINE 96 "./TypeChecking/TableRefs.ag" #-}
                  unwrapSetOfComposite (getTypeAnnotation _selIannotatedTree)
                  {-# LINE 14221 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 98, column 9)
              _idLookups =
                  {-# LINE 98 "./TypeChecking/TableRefs.ag" #-}
                  fromRight [] _selectAttrs
                  {-# LINE 14226 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 99, column 9)
              _qidLookups =
                  {-# LINE 99 "./TypeChecking/TableRefs.ag" #-}
                  [(getAlias "" _aliasIannotatedTree, _idLookups    )]
                  {-# LINE 14231 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 100, column 9)
              _starExpansion =
                  {-# LINE 100 "./TypeChecking/TableRefs.ag" #-}
                  _idLookups
                  {-# LINE 14236 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 101, column 9)
              _qstarExpansion =
                  {-# LINE 101 "./TypeChecking/TableRefs.ag" #-}
                  _qidLookups
                  {-# LINE 14241 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 248, column 9)
              _lhsOlibUpdates =
                  {-# LINE 248 "./TypeChecking/TableRefs.ag" #-}
                  _libUpdates
                  {-# LINE 14246 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 249, column 9)
              _lhsOidLookups =
                  {-# LINE 249 "./TypeChecking/TableRefs.ag" #-}
                  _idLookups
                  {-# LINE 14251 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 250, column 9)
              _lhsOqidLookups =
                  {-# LINE 250 "./TypeChecking/TableRefs.ag" #-}
                  _qidLookups
                  {-# LINE 14256 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 251, column 9)
              _lhsOstarExpansion =
                  {-# LINE 251 "./TypeChecking/TableRefs.ag" #-}
                  _starExpansion
                  {-# LINE 14261 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 252, column 9)
              _lhsOqstarExpansion =
                  {-# LINE 252 "./TypeChecking/TableRefs.ag" #-}
                  _qstarExpansion
                  {-# LINE 14266 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 258, column 9)
              _backTree =
                  {-# LINE 258 "./TypeChecking/TableRefs.ag" #-}
                  SubTref ann_ _selIannotatedTree _aliasIannotatedTree
                  {-# LINE 14271 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SubTref ann_ _selIannotatedTree _aliasIannotatedTree
                  {-# LINE 14276 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SubTref ann_ _selIoriginalTree _aliasIoriginalTree
                  {-# LINE 14281 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14286 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14291 "AstInternal.hs" #-}
              -- copy rule (down)
              _selOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14296 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14301 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14306 "AstInternal.hs" #-}
              ( _selIannotatedTree,_selIlibUpdates,_selIoriginalTree) =
                  (sel_ _selOenv _selOlib )
              ( _aliasIannotatedTree,_aliasIoriginalTree) =
                  (alias_ _aliasOenv _aliasOlib )
          in  ( _lhsOannotatedTree,_lhsOidLookups,_lhsOlibUpdates,_lhsOoriginalTree,_lhsOqidLookups,_lhsOqstarExpansion,_lhsOstarExpansion)))
sem_TableRef_Tref :: Annotation ->
                     String ->
                     T_TableAlias  ->
                     T_TableRef 
sem_TableRef_Tref ann_ tbl_ alias_  =
    (\ _lhsIenv
       _lhsIjlibUpdates
       _lhsIlib ->
         (let _lhsOannotatedTree :: TableRef
              _relType :: (Either [TypeError] ([(String, Type)], [(String, Type)]))
              _idLookups :: ([(String,Type)])
              _qidLookups :: ([(String,[(String,Type)])])
              _starExpansion :: ([(String,Type)])
              _qstarExpansion :: ([(String,[(String,Type)])])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOidLookups :: ([(String,Type)])
              _lhsOqidLookups :: ([(String,[(String,Type)])])
              _lhsOstarExpansion :: ([(String,Type)])
              _lhsOqstarExpansion :: ([(String,[(String,Type)])])
              _lhsOoriginalTree :: TableRef
              _aliasOenv :: Environment
              _aliasOlib :: LocalIdentifierBindings
              _aliasIannotatedTree :: TableAlias
              _aliasIoriginalTree :: TableAlias
              -- "./TypeChecking/TableRefs.ag"(line 33, column 9)
              _lhsOannotatedTree =
                  {-# LINE 33 "./TypeChecking/TableRefs.ag" #-}
                  updateAnnotation (map TypeErrorA _errs     ++) _backTree
                  {-# LINE 14340 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 75, column 9)
              _libUpdates =
                  {-# LINE 75 "./TypeChecking/TableRefs.ag" #-}
                  if null _errs
                    then [LibStackIDs $ ("", _idLookups    ): _qidLookups
                         ,LibSetStarExpansion $ ("", _starExpansion    ): _qstarExpansion    ]
                    else []
                  {-# LINE 14348 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 104, column 9)
              _errs =
                  {-# LINE 104 "./TypeChecking/TableRefs.ag" #-}
                  case _relType     of
                    Left e -> e
                    Right _ -> []
                  {-# LINE 14355 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 108, column 9)
              _relType =
                  {-# LINE 108 "./TypeChecking/TableRefs.ag" #-}
                  envCompositeAttrsPair _lhsIenv [] tbl_
                  {-# LINE 14360 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 109, column 9)
              _relType1 =
                  {-# LINE 109 "./TypeChecking/TableRefs.ag" #-}
                  fromRight ([],[]) _relType
                  {-# LINE 14365 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 110, column 9)
              _pAttrs =
                  {-# LINE 110 "./TypeChecking/TableRefs.ag" #-}
                  fst _relType1
                  {-# LINE 14370 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 111, column 9)
              _sAttrs =
                  {-# LINE 111 "./TypeChecking/TableRefs.ag" #-}
                  snd _relType1
                  {-# LINE 14375 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 113, column 9)
              _idLookups =
                  {-# LINE 113 "./TypeChecking/TableRefs.ag" #-}
                  _pAttrs     ++ _sAttrs
                  {-# LINE 14380 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 114, column 9)
              _alias =
                  {-# LINE 114 "./TypeChecking/TableRefs.ag" #-}
                  getAlias tbl_ _aliasIannotatedTree
                  {-# LINE 14385 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 115, column 9)
              _qidLookups =
                  {-# LINE 115 "./TypeChecking/TableRefs.ag" #-}
                  [(_alias    , _idLookups    )]
                  {-# LINE 14390 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 116, column 9)
              _starExpansion =
                  {-# LINE 116 "./TypeChecking/TableRefs.ag" #-}
                  _pAttrs
                  {-# LINE 14395 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 117, column 9)
              _qstarExpansion =
                  {-# LINE 117 "./TypeChecking/TableRefs.ag" #-}
                  [(_alias    , _pAttrs    )]
                  {-# LINE 14400 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 248, column 9)
              _lhsOlibUpdates =
                  {-# LINE 248 "./TypeChecking/TableRefs.ag" #-}
                  _libUpdates
                  {-# LINE 14405 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 249, column 9)
              _lhsOidLookups =
                  {-# LINE 249 "./TypeChecking/TableRefs.ag" #-}
                  _idLookups
                  {-# LINE 14410 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 250, column 9)
              _lhsOqidLookups =
                  {-# LINE 250 "./TypeChecking/TableRefs.ag" #-}
                  _qidLookups
                  {-# LINE 14415 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 251, column 9)
              _lhsOstarExpansion =
                  {-# LINE 251 "./TypeChecking/TableRefs.ag" #-}
                  _starExpansion
                  {-# LINE 14420 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 252, column 9)
              _lhsOqstarExpansion =
                  {-# LINE 252 "./TypeChecking/TableRefs.ag" #-}
                  _qstarExpansion
                  {-# LINE 14425 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 260, column 9)
              _backTree =
                  {-# LINE 260 "./TypeChecking/TableRefs.ag" #-}
                  Tref ann_ tbl_ _aliasIannotatedTree
                  {-# LINE 14430 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Tref ann_ tbl_ _aliasIannotatedTree
                  {-# LINE 14435 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Tref ann_ tbl_ _aliasIoriginalTree
                  {-# LINE 14440 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14445 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14450 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14455 "AstInternal.hs" #-}
              ( _aliasIannotatedTree,_aliasIoriginalTree) =
                  (alias_ _aliasOenv _aliasOlib )
          in  ( _lhsOannotatedTree,_lhsOidLookups,_lhsOlibUpdates,_lhsOoriginalTree,_lhsOqidLookups,_lhsOqstarExpansion,_lhsOstarExpansion)))
sem_TableRef_TrefFun :: Annotation ->
                        T_Expression  ->
                        T_TableAlias  ->
                        T_TableRef 
sem_TableRef_TrefFun ann_ fn_ alias_  =
    (\ _lhsIenv
       _lhsIjlibUpdates
       _lhsIlib ->
         (let _lhsOannotatedTree :: TableRef
              _eqfunIdens :: (Either [TypeError] (String,[(String,Type)]))
              _idLookups :: ([(String,Type)])
              _qidLookups :: ([(String,[(String,Type)])])
              _starExpansion :: ([(String,Type)])
              _qstarExpansion :: ([(String,[(String,Type)])])
              _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOidLookups :: ([(String,Type)])
              _lhsOqidLookups :: ([(String,[(String,Type)])])
              _lhsOstarExpansion :: ([(String,Type)])
              _lhsOqstarExpansion :: ([(String,[(String,Type)])])
              _lhsOoriginalTree :: TableRef
              _fnOenv :: Environment
              _fnOlib :: LocalIdentifierBindings
              _aliasOenv :: Environment
              _aliasOlib :: LocalIdentifierBindings
              _fnIannotatedTree :: Expression
              _fnIliftedColumnName :: String
              _fnIoriginalTree :: Expression
              _aliasIannotatedTree :: TableAlias
              _aliasIoriginalTree :: TableAlias
              -- "./TypeChecking/TableRefs.ag"(line 33, column 9)
              _lhsOannotatedTree =
                  {-# LINE 33 "./TypeChecking/TableRefs.ag" #-}
                  updateAnnotation (map TypeErrorA _errs     ++) _backTree
                  {-# LINE 14492 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 75, column 9)
              _libUpdates =
                  {-# LINE 75 "./TypeChecking/TableRefs.ag" #-}
                  if null _errs
                    then [LibStackIDs $ ("", _idLookups    ): _qidLookups
                         ,LibSetStarExpansion $ ("", _starExpansion    ): _qstarExpansion    ]
                    else []
                  {-# LINE 14500 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 120, column 9)
              _errs =
                  {-# LINE 120 "./TypeChecking/TableRefs.ag" #-}
                  case _eqfunIdens of
                    Left e -> e
                    Right _ -> []
                  {-# LINE 14507 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 124, column 9)
              _eqfunIdens =
                  {-# LINE 124 "./TypeChecking/TableRefs.ag" #-}
                  funIdens _lhsIenv _alias     _fnIannotatedTree
                  {-# LINE 14512 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 125, column 9)
              _qfunIdens =
                  {-# LINE 125 "./TypeChecking/TableRefs.ag" #-}
                  fromRight ("",[]) _eqfunIdens
                  {-# LINE 14517 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 126, column 9)
              _alias2 =
                  {-# LINE 126 "./TypeChecking/TableRefs.ag" #-}
                  fst _qfunIdens
                  {-# LINE 14522 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 127, column 9)
              _funIdens =
                  {-# LINE 127 "./TypeChecking/TableRefs.ag" #-}
                  snd _qfunIdens
                  {-# LINE 14527 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 128, column 9)
              _alias =
                  {-# LINE 128 "./TypeChecking/TableRefs.ag" #-}
                  getAlias "" _aliasIannotatedTree
                  {-# LINE 14532 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 130, column 9)
              _idLookups =
                  {-# LINE 130 "./TypeChecking/TableRefs.ag" #-}
                  _funIdens
                  {-# LINE 14537 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 131, column 9)
              _qidLookups =
                  {-# LINE 131 "./TypeChecking/TableRefs.ag" #-}
                  [(_alias2, _idLookups    )]
                  {-# LINE 14542 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 132, column 9)
              _starExpansion =
                  {-# LINE 132 "./TypeChecking/TableRefs.ag" #-}
                  _idLookups
                  {-# LINE 14547 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 133, column 9)
              _qstarExpansion =
                  {-# LINE 133 "./TypeChecking/TableRefs.ag" #-}
                  _qidLookups
                  {-# LINE 14552 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 248, column 9)
              _lhsOlibUpdates =
                  {-# LINE 248 "./TypeChecking/TableRefs.ag" #-}
                  _libUpdates
                  {-# LINE 14557 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 249, column 9)
              _lhsOidLookups =
                  {-# LINE 249 "./TypeChecking/TableRefs.ag" #-}
                  _idLookups
                  {-# LINE 14562 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 250, column 9)
              _lhsOqidLookups =
                  {-# LINE 250 "./TypeChecking/TableRefs.ag" #-}
                  _qidLookups
                  {-# LINE 14567 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 251, column 9)
              _lhsOstarExpansion =
                  {-# LINE 251 "./TypeChecking/TableRefs.ag" #-}
                  _starExpansion
                  {-# LINE 14572 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 252, column 9)
              _lhsOqstarExpansion =
                  {-# LINE 252 "./TypeChecking/TableRefs.ag" #-}
                  _qstarExpansion
                  {-# LINE 14577 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 262, column 9)
              _backTree =
                  {-# LINE 262 "./TypeChecking/TableRefs.ag" #-}
                  TrefFun ann_ _fnIannotatedTree _aliasIannotatedTree
                  {-# LINE 14582 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TrefFun ann_ _fnIannotatedTree _aliasIannotatedTree
                  {-# LINE 14587 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TrefFun ann_ _fnIoriginalTree _aliasIoriginalTree
                  {-# LINE 14592 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14597 "AstInternal.hs" #-}
              -- copy rule (down)
              _fnOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14602 "AstInternal.hs" #-}
              -- copy rule (down)
              _fnOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14607 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14612 "AstInternal.hs" #-}
              -- copy rule (down)
              _aliasOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14617 "AstInternal.hs" #-}
              ( _fnIannotatedTree,_fnIliftedColumnName,_fnIoriginalTree) =
                  (fn_ _fnOenv _fnOlib )
              ( _aliasIannotatedTree,_aliasIoriginalTree) =
                  (alias_ _aliasOenv _aliasOlib )
          in  ( _lhsOannotatedTree,_lhsOidLookups,_lhsOlibUpdates,_lhsOoriginalTree,_lhsOqidLookups,_lhsOqstarExpansion,_lhsOstarExpansion)))
-- TableRefList ------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         libUpdates           : [LocalIdentifierBindingsUpdate]
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : TableRef 
         child tl             : TableRefList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type TableRefList  = [(TableRef)]
-- cata
sem_TableRefList :: TableRefList  ->
                    T_TableRefList 
sem_TableRefList list  =
    (Prelude.foldr sem_TableRefList_Cons sem_TableRefList_Nil (Prelude.map sem_TableRef list) )
-- semantic domain
type T_TableRefList  = Environment ->
                       LocalIdentifierBindings ->
                       ( TableRefList,([LocalIdentifierBindingsUpdate]),TableRefList)
data Inh_TableRefList  = Inh_TableRefList {env_Inh_TableRefList :: Environment,lib_Inh_TableRefList :: LocalIdentifierBindings}
data Syn_TableRefList  = Syn_TableRefList {annotatedTree_Syn_TableRefList :: TableRefList,libUpdates_Syn_TableRefList :: [LocalIdentifierBindingsUpdate],originalTree_Syn_TableRefList :: TableRefList}
wrap_TableRefList :: T_TableRefList  ->
                     Inh_TableRefList  ->
                     Syn_TableRefList 
wrap_TableRefList sem (Inh_TableRefList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TableRefList _lhsOannotatedTree _lhsOlibUpdates _lhsOoriginalTree ))
sem_TableRefList_Cons :: T_TableRef  ->
                         T_TableRefList  ->
                         T_TableRefList 
sem_TableRefList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _hdOjlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: TableRefList
              _lhsOoriginalTree :: TableRefList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: TableRef
              _hdIidLookups :: ([(String,Type)])
              _hdIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _hdIoriginalTree :: TableRef
              _hdIqidLookups :: ([(String,[(String,Type)])])
              _hdIqstarExpansion :: ([(String,[(String,Type)])])
              _hdIstarExpansion :: ([(String,Type)])
              _tlIannotatedTree :: TableRefList
              _tlIlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _tlIoriginalTree :: TableRefList
              -- "./TypeChecking/TableRefs.ag"(line 40, column 9)
              _lhsOlibUpdates =
                  {-# LINE 40 "./TypeChecking/TableRefs.ag" #-}
                  _hdIlibUpdates
                  {-# LINE 14692 "AstInternal.hs" #-}
              -- "./TypeChecking/TableRefs.ag"(line 197, column 12)
              _hdOjlibUpdates =
                  {-# LINE 197 "./TypeChecking/TableRefs.ag" #-}
                  []
                  {-# LINE 14697 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 14702 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 14707 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 14712 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14717 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14722 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14727 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 14732 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 14737 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIidLookups,_hdIlibUpdates,_hdIoriginalTree,_hdIqidLookups,_hdIqstarExpansion,_hdIstarExpansion) =
                  (hd_ _hdOenv _hdOjlibUpdates _hdOlib )
              ( _tlIannotatedTree,_tlIlibUpdates,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOoriginalTree)))
sem_TableRefList_Nil :: T_TableRefList 
sem_TableRefList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOlibUpdates :: ([LocalIdentifierBindingsUpdate])
              _lhsOannotatedTree :: TableRefList
              _lhsOoriginalTree :: TableRefList
              -- "./TypeChecking/TableRefs.ag"(line 38, column 9)
              _lhsOlibUpdates =
                  {-# LINE 38 "./TypeChecking/TableRefs.ag" #-}
                  []
                  {-# LINE 14754 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 14759 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 14764 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 14769 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14774 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOlibUpdates,_lhsOoriginalTree)))
-- TriggerEvent ------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative TDelete:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative TInsert:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative TUpdate:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data TriggerEvent  = TDelete 
                   | TInsert 
                   | TUpdate 
                   deriving ( Data,Eq,Show,Typeable)
-- cata
sem_TriggerEvent :: TriggerEvent  ->
                    T_TriggerEvent 
sem_TriggerEvent (TDelete )  =
    (sem_TriggerEvent_TDelete )
sem_TriggerEvent (TInsert )  =
    (sem_TriggerEvent_TInsert )
sem_TriggerEvent (TUpdate )  =
    (sem_TriggerEvent_TUpdate )
-- semantic domain
type T_TriggerEvent  = Environment ->
                       LocalIdentifierBindings ->
                       ( TriggerEvent,TriggerEvent)
data Inh_TriggerEvent  = Inh_TriggerEvent {env_Inh_TriggerEvent :: Environment,lib_Inh_TriggerEvent :: LocalIdentifierBindings}
data Syn_TriggerEvent  = Syn_TriggerEvent {annotatedTree_Syn_TriggerEvent :: TriggerEvent,originalTree_Syn_TriggerEvent :: TriggerEvent}
wrap_TriggerEvent :: T_TriggerEvent  ->
                     Inh_TriggerEvent  ->
                     Syn_TriggerEvent 
wrap_TriggerEvent sem (Inh_TriggerEvent _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TriggerEvent _lhsOannotatedTree _lhsOoriginalTree ))
sem_TriggerEvent_TDelete :: T_TriggerEvent 
sem_TriggerEvent_TDelete  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TriggerEvent
              _lhsOoriginalTree :: TriggerEvent
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TDelete
                  {-# LINE 14835 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TDelete
                  {-# LINE 14840 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 14845 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14850 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_TriggerEvent_TInsert :: T_TriggerEvent 
sem_TriggerEvent_TInsert  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TriggerEvent
              _lhsOoriginalTree :: TriggerEvent
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TInsert
                  {-# LINE 14862 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TInsert
                  {-# LINE 14867 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 14872 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14877 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_TriggerEvent_TUpdate :: T_TriggerEvent 
sem_TriggerEvent_TUpdate  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TriggerEvent
              _lhsOoriginalTree :: TriggerEvent
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TUpdate
                  {-# LINE 14889 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TUpdate
                  {-# LINE 14894 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 14899 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14904 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- TriggerFire -------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative EachRow:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative EachStatement:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data TriggerFire  = EachRow 
                  | EachStatement 
                  deriving ( Data,Eq,Show,Typeable)
-- cata
sem_TriggerFire :: TriggerFire  ->
                   T_TriggerFire 
sem_TriggerFire (EachRow )  =
    (sem_TriggerFire_EachRow )
sem_TriggerFire (EachStatement )  =
    (sem_TriggerFire_EachStatement )
-- semantic domain
type T_TriggerFire  = Environment ->
                      LocalIdentifierBindings ->
                      ( TriggerFire,TriggerFire)
data Inh_TriggerFire  = Inh_TriggerFire {env_Inh_TriggerFire :: Environment,lib_Inh_TriggerFire :: LocalIdentifierBindings}
data Syn_TriggerFire  = Syn_TriggerFire {annotatedTree_Syn_TriggerFire :: TriggerFire,originalTree_Syn_TriggerFire :: TriggerFire}
wrap_TriggerFire :: T_TriggerFire  ->
                    Inh_TriggerFire  ->
                    Syn_TriggerFire 
wrap_TriggerFire sem (Inh_TriggerFire _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TriggerFire _lhsOannotatedTree _lhsOoriginalTree ))
sem_TriggerFire_EachRow :: T_TriggerFire 
sem_TriggerFire_EachRow  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TriggerFire
              _lhsOoriginalTree :: TriggerFire
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  EachRow
                  {-# LINE 14958 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  EachRow
                  {-# LINE 14963 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 14968 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 14973 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_TriggerFire_EachStatement :: T_TriggerFire 
sem_TriggerFire_EachStatement  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TriggerFire
              _lhsOoriginalTree :: TriggerFire
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  EachStatement
                  {-# LINE 14985 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  EachStatement
                  {-# LINE 14990 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 14995 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15000 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- TriggerWhen -------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative TriggerAfter:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative TriggerBefore:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data TriggerWhen  = TriggerAfter 
                  | TriggerBefore 
                  deriving ( Data,Eq,Show,Typeable)
-- cata
sem_TriggerWhen :: TriggerWhen  ->
                   T_TriggerWhen 
sem_TriggerWhen (TriggerAfter )  =
    (sem_TriggerWhen_TriggerAfter )
sem_TriggerWhen (TriggerBefore )  =
    (sem_TriggerWhen_TriggerBefore )
-- semantic domain
type T_TriggerWhen  = Environment ->
                      LocalIdentifierBindings ->
                      ( TriggerWhen,TriggerWhen)
data Inh_TriggerWhen  = Inh_TriggerWhen {env_Inh_TriggerWhen :: Environment,lib_Inh_TriggerWhen :: LocalIdentifierBindings}
data Syn_TriggerWhen  = Syn_TriggerWhen {annotatedTree_Syn_TriggerWhen :: TriggerWhen,originalTree_Syn_TriggerWhen :: TriggerWhen}
wrap_TriggerWhen :: T_TriggerWhen  ->
                    Inh_TriggerWhen  ->
                    Syn_TriggerWhen 
wrap_TriggerWhen sem (Inh_TriggerWhen _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TriggerWhen _lhsOannotatedTree _lhsOoriginalTree ))
sem_TriggerWhen_TriggerAfter :: T_TriggerWhen 
sem_TriggerWhen_TriggerAfter  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TriggerWhen
              _lhsOoriginalTree :: TriggerWhen
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TriggerAfter
                  {-# LINE 15054 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TriggerAfter
                  {-# LINE 15059 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15064 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15069 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_TriggerWhen_TriggerBefore :: T_TriggerWhen 
sem_TriggerWhen_TriggerBefore  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: TriggerWhen
              _lhsOoriginalTree :: TriggerWhen
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TriggerBefore
                  {-# LINE 15081 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TriggerBefore
                  {-# LINE 15086 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15091 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15096 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
-- TypeAttributeDef --------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         attrName             : String
         namedType            : Type
         originalTree         : SELF 
   alternatives:
      alternative TypeAttDef:
         child ann            : {Annotation}
         child name           : {String}
         child typ            : TypeName 
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data TypeAttributeDef  = TypeAttDef (Annotation) (String) (TypeName) 
                       deriving ( Data,Eq,Show,Typeable)
-- cata
sem_TypeAttributeDef :: TypeAttributeDef  ->
                        T_TypeAttributeDef 
sem_TypeAttributeDef (TypeAttDef _ann _name _typ )  =
    (sem_TypeAttributeDef_TypeAttDef _ann _name (sem_TypeName _typ ) )
-- semantic domain
type T_TypeAttributeDef  = Environment ->
                           LocalIdentifierBindings ->
                           ( TypeAttributeDef,String,Type,TypeAttributeDef)
data Inh_TypeAttributeDef  = Inh_TypeAttributeDef {env_Inh_TypeAttributeDef :: Environment,lib_Inh_TypeAttributeDef :: LocalIdentifierBindings}
data Syn_TypeAttributeDef  = Syn_TypeAttributeDef {annotatedTree_Syn_TypeAttributeDef :: TypeAttributeDef,attrName_Syn_TypeAttributeDef :: String,namedType_Syn_TypeAttributeDef :: Type,originalTree_Syn_TypeAttributeDef :: TypeAttributeDef}
wrap_TypeAttributeDef :: T_TypeAttributeDef  ->
                         Inh_TypeAttributeDef  ->
                         Syn_TypeAttributeDef 
wrap_TypeAttributeDef sem (Inh_TypeAttributeDef _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOattrName,_lhsOnamedType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TypeAttributeDef _lhsOannotatedTree _lhsOattrName _lhsOnamedType _lhsOoriginalTree ))
sem_TypeAttributeDef_TypeAttDef :: Annotation ->
                                   String ->
                                   T_TypeName  ->
                                   T_TypeAttributeDef 
sem_TypeAttributeDef_TypeAttDef ann_ name_ typ_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOattrName :: String
              _lhsOnamedType :: Type
              _lhsOannotatedTree :: TypeAttributeDef
              _lhsOoriginalTree :: TypeAttributeDef
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              -- "./TypeChecking/MiscCreates.ag"(line 40, column 9)
              _lhsOattrName =
                  {-# LINE 40 "./TypeChecking/MiscCreates.ag" #-}
                  name_
                  {-# LINE 15158 "AstInternal.hs" #-}
              -- "./TypeChecking/MiscCreates.ag"(line 41, column 9)
              _lhsOnamedType =
                  {-# LINE 41 "./TypeChecking/MiscCreates.ag" #-}
                  _typInamedType
                  {-# LINE 15163 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  TypeAttDef ann_ name_ _typIannotatedTree
                  {-# LINE 15168 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  TypeAttDef ann_ name_ _typIoriginalTree
                  {-# LINE 15173 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15178 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15183 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15188 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15193 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
          in  ( _lhsOannotatedTree,_lhsOattrName,_lhsOnamedType,_lhsOoriginalTree)))
-- TypeAttributeDefList ----------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         attrs                : [(String, Type)]
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : TypeAttributeDef 
         child tl             : TypeAttributeDefList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type TypeAttributeDefList  = [(TypeAttributeDef)]
-- cata
sem_TypeAttributeDefList :: TypeAttributeDefList  ->
                            T_TypeAttributeDefList 
sem_TypeAttributeDefList list  =
    (Prelude.foldr sem_TypeAttributeDefList_Cons sem_TypeAttributeDefList_Nil (Prelude.map sem_TypeAttributeDef list) )
-- semantic domain
type T_TypeAttributeDefList  = Environment ->
                               LocalIdentifierBindings ->
                               ( TypeAttributeDefList,([(String, Type)]),TypeAttributeDefList)
data Inh_TypeAttributeDefList  = Inh_TypeAttributeDefList {env_Inh_TypeAttributeDefList :: Environment,lib_Inh_TypeAttributeDefList :: LocalIdentifierBindings}
data Syn_TypeAttributeDefList  = Syn_TypeAttributeDefList {annotatedTree_Syn_TypeAttributeDefList :: TypeAttributeDefList,attrs_Syn_TypeAttributeDefList :: [(String, Type)],originalTree_Syn_TypeAttributeDefList :: TypeAttributeDefList}
wrap_TypeAttributeDefList :: T_TypeAttributeDefList  ->
                             Inh_TypeAttributeDefList  ->
                             Syn_TypeAttributeDefList 
wrap_TypeAttributeDefList sem (Inh_TypeAttributeDefList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOattrs,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TypeAttributeDefList _lhsOannotatedTree _lhsOattrs _lhsOoriginalTree ))
sem_TypeAttributeDefList_Cons :: T_TypeAttributeDef  ->
                                 T_TypeAttributeDefList  ->
                                 T_TypeAttributeDefList 
sem_TypeAttributeDefList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOattrs :: ([(String, Type)])
              _lhsOannotatedTree :: TypeAttributeDefList
              _lhsOoriginalTree :: TypeAttributeDefList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: TypeAttributeDef
              _hdIattrName :: String
              _hdInamedType :: Type
              _hdIoriginalTree :: TypeAttributeDef
              _tlIannotatedTree :: TypeAttributeDefList
              _tlIattrs :: ([(String, Type)])
              _tlIoriginalTree :: TypeAttributeDefList
              -- "./TypeChecking/MiscCreates.ag"(line 46, column 12)
              _lhsOattrs =
                  {-# LINE 46 "./TypeChecking/MiscCreates.ag" #-}
                  (_hdIattrName, _hdInamedType) : _tlIattrs
                  {-# LINE 15262 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 15267 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 15272 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15277 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15282 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15287 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15292 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15297 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15302 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIattrName,_hdInamedType,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIattrs,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOattrs,_lhsOoriginalTree)))
sem_TypeAttributeDefList_Nil :: T_TypeAttributeDefList 
sem_TypeAttributeDefList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOattrs :: ([(String, Type)])
              _lhsOannotatedTree :: TypeAttributeDefList
              _lhsOoriginalTree :: TypeAttributeDefList
              -- "./TypeChecking/MiscCreates.ag"(line 47, column 11)
              _lhsOattrs =
                  {-# LINE 47 "./TypeChecking/MiscCreates.ag" #-}
                  []
                  {-# LINE 15319 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 15324 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 15329 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15334 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15339 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOattrs,_lhsOoriginalTree)))
-- TypeName ----------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         namedType            : Type
         originalTree         : SELF 
   alternatives:
      alternative ArrayTypeName:
         child ann            : {Annotation}
         child typ            : TypeName 
         visit 0:
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative PrecTypeName:
         child ann            : {Annotation}
         child tn             : {String}
         child prec           : {Integer}
         visit 0:
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative SetOfTypeName:
         child ann            : {Annotation}
         child typ            : TypeName 
         visit 0:
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
      alternative SimpleTypeName:
         child ann            : {Annotation}
         child tn             : {String}
         visit 0:
            local tpe         : _
            local backTree    : _
            local annotatedTree : _
            local originalTree : _
-}
data TypeName  = ArrayTypeName (Annotation) (TypeName) 
               | PrecTypeName (Annotation) (String) (Integer) 
               | SetOfTypeName (Annotation) (TypeName) 
               | SimpleTypeName (Annotation) (String) 
               deriving ( Data,Eq,Show,Typeable)
-- cata
sem_TypeName :: TypeName  ->
                T_TypeName 
sem_TypeName (ArrayTypeName _ann _typ )  =
    (sem_TypeName_ArrayTypeName _ann (sem_TypeName _typ ) )
sem_TypeName (PrecTypeName _ann _tn _prec )  =
    (sem_TypeName_PrecTypeName _ann _tn _prec )
sem_TypeName (SetOfTypeName _ann _typ )  =
    (sem_TypeName_SetOfTypeName _ann (sem_TypeName _typ ) )
sem_TypeName (SimpleTypeName _ann _tn )  =
    (sem_TypeName_SimpleTypeName _ann _tn )
-- semantic domain
type T_TypeName  = Environment ->
                   LocalIdentifierBindings ->
                   ( TypeName,Type,TypeName)
data Inh_TypeName  = Inh_TypeName {env_Inh_TypeName :: Environment,lib_Inh_TypeName :: LocalIdentifierBindings}
data Syn_TypeName  = Syn_TypeName {annotatedTree_Syn_TypeName :: TypeName,namedType_Syn_TypeName :: Type,originalTree_Syn_TypeName :: TypeName}
wrap_TypeName :: T_TypeName  ->
                 Inh_TypeName  ->
                 Syn_TypeName 
wrap_TypeName sem (Inh_TypeName _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TypeName _lhsOannotatedTree _lhsOnamedType _lhsOoriginalTree ))
sem_TypeName_ArrayTypeName :: Annotation ->
                              T_TypeName  ->
                              T_TypeName 
sem_TypeName_ArrayTypeName ann_ typ_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedType :: Type
              _lhsOannotatedTree :: TypeName
              _lhsOoriginalTree :: TypeName
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              -- "./TypeChecking/Misc.ag"(line 19, column 10)
              _lhsOnamedType =
                  {-# LINE 19 "./TypeChecking/Misc.ag" #-}
                  tpeToT _tpe
                  {-# LINE 15433 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 20, column 10)
              _lhsOannotatedTree =
                  {-# LINE 20 "./TypeChecking/Misc.ag" #-}
                  updateAnnotation
                    ((map TypeErrorA $ getErrors _tpe    ) ++)
                    _backTree
                  {-# LINE 15440 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 30, column 9)
              _tpe =
                  {-# LINE 30 "./TypeChecking/Misc.ag" #-}
                  dependsOnRTpe [_typInamedType] $ Right $ ArrayType _typInamedType
                  {-# LINE 15445 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 31, column 9)
              _backTree =
                  {-# LINE 31 "./TypeChecking/Misc.ag" #-}
                  ArrayTypeName ann_ _typIannotatedTree
                  {-# LINE 15450 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  ArrayTypeName ann_ _typIannotatedTree
                  {-# LINE 15455 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  ArrayTypeName ann_ _typIoriginalTree
                  {-# LINE 15460 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15465 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15470 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15475 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
          in  ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree)))
sem_TypeName_PrecTypeName :: Annotation ->
                             String ->
                             Integer ->
                             T_TypeName 
sem_TypeName_PrecTypeName ann_ tn_ prec_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedType :: Type
              _lhsOannotatedTree :: TypeName
              _lhsOoriginalTree :: TypeName
              -- "./TypeChecking/Misc.ag"(line 19, column 10)
              _lhsOnamedType =
                  {-# LINE 19 "./TypeChecking/Misc.ag" #-}
                  tpeToT _tpe
                  {-# LINE 15493 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 20, column 10)
              _lhsOannotatedTree =
                  {-# LINE 20 "./TypeChecking/Misc.ag" #-}
                  updateAnnotation
                    ((map TypeErrorA $ getErrors _tpe    ) ++)
                    _backTree
                  {-# LINE 15500 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 36, column 9)
              _tpe =
                  {-# LINE 36 "./TypeChecking/Misc.ag" #-}
                  envLookupType _lhsIenv $ canonicalizeTypeName tn_
                  {-# LINE 15505 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 37, column 9)
              _backTree =
                  {-# LINE 37 "./TypeChecking/Misc.ag" #-}
                  PrecTypeName ann_ tn_ prec_
                  {-# LINE 15510 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  PrecTypeName ann_ tn_ prec_
                  {-# LINE 15515 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  PrecTypeName ann_ tn_ prec_
                  {-# LINE 15520 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15525 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree)))
sem_TypeName_SetOfTypeName :: Annotation ->
                              T_TypeName  ->
                              T_TypeName 
sem_TypeName_SetOfTypeName ann_ typ_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedType :: Type
              _lhsOannotatedTree :: TypeName
              _lhsOoriginalTree :: TypeName
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              -- "./TypeChecking/Misc.ag"(line 19, column 10)
              _lhsOnamedType =
                  {-# LINE 19 "./TypeChecking/Misc.ag" #-}
                  tpeToT _tpe
                  {-# LINE 15545 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 20, column 10)
              _lhsOannotatedTree =
                  {-# LINE 20 "./TypeChecking/Misc.ag" #-}
                  updateAnnotation
                    ((map TypeErrorA $ getErrors _tpe    ) ++)
                    _backTree
                  {-# LINE 15552 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 33, column 9)
              _tpe =
                  {-# LINE 33 "./TypeChecking/Misc.ag" #-}
                  dependsOnRTpe [_typInamedType] $ Right $ SetOfType _typInamedType
                  {-# LINE 15557 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 34, column 9)
              _backTree =
                  {-# LINE 34 "./TypeChecking/Misc.ag" #-}
                  SetOfTypeName ann_ _typIannotatedTree
                  {-# LINE 15562 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SetOfTypeName ann_ _typIannotatedTree
                  {-# LINE 15567 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SetOfTypeName ann_ _typIoriginalTree
                  {-# LINE 15572 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15577 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15582 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15587 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
          in  ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree)))
sem_TypeName_SimpleTypeName :: Annotation ->
                               String ->
                               T_TypeName 
sem_TypeName_SimpleTypeName ann_ tn_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedType :: Type
              _lhsOannotatedTree :: TypeName
              _lhsOoriginalTree :: TypeName
              -- "./TypeChecking/Misc.ag"(line 19, column 10)
              _lhsOnamedType =
                  {-# LINE 19 "./TypeChecking/Misc.ag" #-}
                  tpeToT _tpe
                  {-# LINE 15604 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 20, column 10)
              _lhsOannotatedTree =
                  {-# LINE 20 "./TypeChecking/Misc.ag" #-}
                  updateAnnotation
                    ((map TypeErrorA $ getErrors _tpe    ) ++)
                    _backTree
                  {-# LINE 15611 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 27, column 9)
              _tpe =
                  {-# LINE 27 "./TypeChecking/Misc.ag" #-}
                  envLookupType _lhsIenv $ canonicalizeTypeName tn_
                  {-# LINE 15616 "AstInternal.hs" #-}
              -- "./TypeChecking/Misc.ag"(line 28, column 9)
              _backTree =
                  {-# LINE 28 "./TypeChecking/Misc.ag" #-}
                  SimpleTypeName ann_ tn_
                  {-# LINE 15621 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  SimpleTypeName ann_ tn_
                  {-# LINE 15626 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  SimpleTypeName ann_ tn_
                  {-# LINE 15631 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15636 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOnamedType,_lhsOoriginalTree)))
-- TypeNameList ------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         namedTypes           : [Type]
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : TypeName 
         child tl             : TypeNameList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type TypeNameList  = [(TypeName)]
-- cata
sem_TypeNameList :: TypeNameList  ->
                    T_TypeNameList 
sem_TypeNameList list  =
    (Prelude.foldr sem_TypeNameList_Cons sem_TypeNameList_Nil (Prelude.map sem_TypeName list) )
-- semantic domain
type T_TypeNameList  = Environment ->
                       LocalIdentifierBindings ->
                       ( TypeNameList,([Type]),TypeNameList)
data Inh_TypeNameList  = Inh_TypeNameList {env_Inh_TypeNameList :: Environment,lib_Inh_TypeNameList :: LocalIdentifierBindings}
data Syn_TypeNameList  = Syn_TypeNameList {annotatedTree_Syn_TypeNameList :: TypeNameList,namedTypes_Syn_TypeNameList :: [Type],originalTree_Syn_TypeNameList :: TypeNameList}
wrap_TypeNameList :: T_TypeNameList  ->
                     Inh_TypeNameList  ->
                     Syn_TypeNameList 
wrap_TypeNameList sem (Inh_TypeNameList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOnamedTypes,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_TypeNameList _lhsOannotatedTree _lhsOnamedTypes _lhsOoriginalTree ))
sem_TypeNameList_Cons :: T_TypeName  ->
                         T_TypeNameList  ->
                         T_TypeNameList 
sem_TypeNameList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedTypes :: ([Type])
              _lhsOannotatedTree :: TypeNameList
              _lhsOoriginalTree :: TypeNameList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: TypeName
              _hdInamedType :: Type
              _hdIoriginalTree :: TypeName
              _tlIannotatedTree :: TypeNameList
              _tlInamedTypes :: ([Type])
              _tlIoriginalTree :: TypeNameList
              -- "./TypeChecking/Drops.ag"(line 30, column 12)
              _lhsOnamedTypes =
                  {-# LINE 30 "./TypeChecking/Drops.ag" #-}
                  _hdInamedType : _tlInamedTypes
                  {-# LINE 15702 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 15707 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 15712 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15717 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15722 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15727 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15732 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15737 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15742 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdInamedType,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlInamedTypes,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOnamedTypes,_lhsOoriginalTree)))
sem_TypeNameList_Nil :: T_TypeNameList 
sem_TypeNameList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOnamedTypes :: ([Type])
              _lhsOannotatedTree :: TypeNameList
              _lhsOoriginalTree :: TypeNameList
              -- "./TypeChecking/Drops.ag"(line 31, column 11)
              _lhsOnamedTypes =
                  {-# LINE 31 "./TypeChecking/Drops.ag" #-}
                  []
                  {-# LINE 15759 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 15764 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 15769 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15774 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15779 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOnamedTypes,_lhsOoriginalTree)))
-- VarDef ------------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         def                  : (String,Type)
         originalTree         : SELF 
   alternatives:
      alternative VarDef:
         child ann            : {Annotation}
         child name           : {String}
         child typ            : TypeName 
         child value          : {Maybe Expression}
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data VarDef  = VarDef (Annotation) (String) (TypeName) (Maybe Expression) 
             deriving ( Data,Eq,Show,Typeable)
-- cata
sem_VarDef :: VarDef  ->
              T_VarDef 
sem_VarDef (VarDef _ann _name _typ _value )  =
    (sem_VarDef_VarDef _ann _name (sem_TypeName _typ ) _value )
-- semantic domain
type T_VarDef  = Environment ->
                 LocalIdentifierBindings ->
                 ( VarDef,((String,Type)),VarDef)
data Inh_VarDef  = Inh_VarDef {env_Inh_VarDef :: Environment,lib_Inh_VarDef :: LocalIdentifierBindings}
data Syn_VarDef  = Syn_VarDef {annotatedTree_Syn_VarDef :: VarDef,def_Syn_VarDef :: (String,Type),originalTree_Syn_VarDef :: VarDef}
wrap_VarDef :: T_VarDef  ->
               Inh_VarDef  ->
               Syn_VarDef 
wrap_VarDef sem (Inh_VarDef _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOdef,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_VarDef _lhsOannotatedTree _lhsOdef _lhsOoriginalTree ))
sem_VarDef_VarDef :: Annotation ->
                     String ->
                     T_TypeName  ->
                     (Maybe Expression) ->
                     T_VarDef 
sem_VarDef_VarDef ann_ name_ typ_ value_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOdef :: ((String,Type))
              _lhsOannotatedTree :: VarDef
              _lhsOoriginalTree :: VarDef
              _typOenv :: Environment
              _typOlib :: LocalIdentifierBindings
              _typIannotatedTree :: TypeName
              _typInamedType :: Type
              _typIoriginalTree :: TypeName
              -- "./TypeChecking/CreateFunction.ag"(line 131, column 14)
              _lhsOdef =
                  {-# LINE 131 "./TypeChecking/CreateFunction.ag" #-}
                  (name_, if _typInamedType == Pseudo Record then PgRecord Nothing else _typInamedType)
                  {-# LINE 15841 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  VarDef ann_ name_ _typIannotatedTree value_
                  {-# LINE 15846 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  VarDef ann_ name_ _typIoriginalTree value_
                  {-# LINE 15851 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15856 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15861 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15866 "AstInternal.hs" #-}
              -- copy rule (down)
              _typOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15871 "AstInternal.hs" #-}
              ( _typIannotatedTree,_typInamedType,_typIoriginalTree) =
                  (typ_ _typOenv _typOlib )
          in  ( _lhsOannotatedTree,_lhsOdef,_lhsOoriginalTree)))
-- VarDefList --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         defs                 : [(String,Type)]
         originalTree         : SELF 
   alternatives:
      alternative Cons:
         child hd             : VarDef 
         child tl             : VarDefList 
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Nil:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
type VarDefList  = [(VarDef)]
-- cata
sem_VarDefList :: VarDefList  ->
                  T_VarDefList 
sem_VarDefList list  =
    (Prelude.foldr sem_VarDefList_Cons sem_VarDefList_Nil (Prelude.map sem_VarDef list) )
-- semantic domain
type T_VarDefList  = Environment ->
                     LocalIdentifierBindings ->
                     ( VarDefList,([(String,Type)]),VarDefList)
data Inh_VarDefList  = Inh_VarDefList {env_Inh_VarDefList :: Environment,lib_Inh_VarDefList :: LocalIdentifierBindings}
data Syn_VarDefList  = Syn_VarDefList {annotatedTree_Syn_VarDefList :: VarDefList,defs_Syn_VarDefList :: [(String,Type)],originalTree_Syn_VarDefList :: VarDefList}
wrap_VarDefList :: T_VarDefList  ->
                   Inh_VarDefList  ->
                   Syn_VarDefList 
wrap_VarDefList sem (Inh_VarDefList _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOdefs,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_VarDefList _lhsOannotatedTree _lhsOdefs _lhsOoriginalTree ))
sem_VarDefList_Cons :: T_VarDef  ->
                       T_VarDefList  ->
                       T_VarDefList 
sem_VarDefList_Cons hd_ tl_  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOdefs :: ([(String,Type)])
              _lhsOannotatedTree :: VarDefList
              _lhsOoriginalTree :: VarDefList
              _hdOenv :: Environment
              _hdOlib :: LocalIdentifierBindings
              _tlOenv :: Environment
              _tlOlib :: LocalIdentifierBindings
              _hdIannotatedTree :: VarDef
              _hdIdef :: ((String,Type))
              _hdIoriginalTree :: VarDef
              _tlIannotatedTree :: VarDefList
              _tlIdefs :: ([(String,Type)])
              _tlIoriginalTree :: VarDefList
              -- "./TypeChecking/CreateFunction.ag"(line 134, column 12)
              _lhsOdefs =
                  {-# LINE 134 "./TypeChecking/CreateFunction.ag" #-}
                  _hdIdef : _tlIdefs
                  {-# LINE 15939 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIannotatedTree _tlIannotatedTree
                  {-# LINE 15944 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  (:) _hdIoriginalTree _tlIoriginalTree
                  {-# LINE 15949 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 15954 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 15959 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15964 "AstInternal.hs" #-}
              -- copy rule (down)
              _hdOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15969 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOenv =
                  {-# LINE 56 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIenv
                  {-# LINE 15974 "AstInternal.hs" #-}
              -- copy rule (down)
              _tlOlib =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _lhsIlib
                  {-# LINE 15979 "AstInternal.hs" #-}
              ( _hdIannotatedTree,_hdIdef,_hdIoriginalTree) =
                  (hd_ _hdOenv _hdOlib )
              ( _tlIannotatedTree,_tlIdefs,_tlIoriginalTree) =
                  (tl_ _tlOenv _tlOlib )
          in  ( _lhsOannotatedTree,_lhsOdefs,_lhsOoriginalTree)))
sem_VarDefList_Nil :: T_VarDefList 
sem_VarDefList_Nil  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOdefs :: ([(String,Type)])
              _lhsOannotatedTree :: VarDefList
              _lhsOoriginalTree :: VarDefList
              -- "./TypeChecking/CreateFunction.ag"(line 135, column 11)
              _lhsOdefs =
                  {-# LINE 135 "./TypeChecking/CreateFunction.ag" #-}
                  []
                  {-# LINE 15996 "AstInternal.hs" #-}
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 16001 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  []
                  {-# LINE 16006 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 16011 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 16016 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOdefs,_lhsOoriginalTree)))
-- Volatility --------------------------------------------------
{-
   visit 0:
      inherited attributes:
         env                  : Environment
         lib                  : LocalIdentifierBindings
      synthesized attributes:
         annotatedTree        : SELF 
         originalTree         : SELF 
   alternatives:
      alternative Immutable:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Stable:
         visit 0:
            local annotatedTree : _
            local originalTree : _
      alternative Volatile:
         visit 0:
            local annotatedTree : _
            local originalTree : _
-}
data Volatility  = Immutable 
                 | Stable 
                 | Volatile 
                 deriving ( Data,Eq,Show,Typeable)
-- cata
sem_Volatility :: Volatility  ->
                  T_Volatility 
sem_Volatility (Immutable )  =
    (sem_Volatility_Immutable )
sem_Volatility (Stable )  =
    (sem_Volatility_Stable )
sem_Volatility (Volatile )  =
    (sem_Volatility_Volatile )
-- semantic domain
type T_Volatility  = Environment ->
                     LocalIdentifierBindings ->
                     ( Volatility,Volatility)
data Inh_Volatility  = Inh_Volatility {env_Inh_Volatility :: Environment,lib_Inh_Volatility :: LocalIdentifierBindings}
data Syn_Volatility  = Syn_Volatility {annotatedTree_Syn_Volatility :: Volatility,originalTree_Syn_Volatility :: Volatility}
wrap_Volatility :: T_Volatility  ->
                   Inh_Volatility  ->
                   Syn_Volatility 
wrap_Volatility sem (Inh_Volatility _lhsIenv _lhsIlib )  =
    (let ( _lhsOannotatedTree,_lhsOoriginalTree) =
             (sem _lhsIenv _lhsIlib )
     in  (Syn_Volatility _lhsOannotatedTree _lhsOoriginalTree ))
sem_Volatility_Immutable :: T_Volatility 
sem_Volatility_Immutable  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Volatility
              _lhsOoriginalTree :: Volatility
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Immutable
                  {-# LINE 16077 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Immutable
                  {-# LINE 16082 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 16087 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 16092 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Volatility_Stable :: T_Volatility 
sem_Volatility_Stable  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Volatility
              _lhsOoriginalTree :: Volatility
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Stable
                  {-# LINE 16104 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Stable
                  {-# LINE 16109 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 16114 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 16119 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))
sem_Volatility_Volatile :: T_Volatility 
sem_Volatility_Volatile  =
    (\ _lhsIenv
       _lhsIlib ->
         (let _lhsOannotatedTree :: Volatility
              _lhsOoriginalTree :: Volatility
              -- self rule
              _annotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  Volatile
                  {-# LINE 16131 "AstInternal.hs" #-}
              -- self rule
              _originalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  Volatile
                  {-# LINE 16136 "AstInternal.hs" #-}
              -- self rule
              _lhsOannotatedTree =
                  {-# LINE 57 "./TypeChecking/TypeChecking.ag" #-}
                  _annotatedTree
                  {-# LINE 16141 "AstInternal.hs" #-}
              -- self rule
              _lhsOoriginalTree =
                  {-# LINE 63 "./TypeChecking/TypeChecking.ag" #-}
                  _originalTree
                  {-# LINE 16146 "AstInternal.hs" #-}
          in  ( _lhsOannotatedTree,_lhsOoriginalTree)))