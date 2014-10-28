module Tail.Output where

import Prelude hiding (exp)

import Language.Haskell.Exts.Syntax as Hs
import Language.Haskell.Exts.SrcLoc (noLoc)
import Language.Haskell.Exts.Pretty (prettyPrint)

import qualified Tail.SimpleAccAst as A

prettyPrintProgram = prettyPrint . outputProgram

qualAcc :: Name -> QName
qualAcc name = Qual (ModuleName "Acc") name

qualPrelude :: Name -> QName
qualPrelude name = Qual (ModuleName "P") name

name :: A.Name -> Name
name (A.Ident n) = Ident n
name (A.Symbol n) = Symbol n

qname :: A.QName -> QName
qname (A.UnQual n)     = UnQual $ name n
qname (A.Prelude n)    = Qual (ModuleName "P") $ name n
qname (A.Accelerate n) = Qual (ModuleName "Acc") $ name n
qname (A.Primitive n)  = UnQual $ name n

infixOp :: A.QName -> QOp
infixOp (A.UnQual n)     = QVarOp $ UnQual $ name n
infixOp (A.Prelude n)    = QVarOp $ Qual (ModuleName "P") $ name n
infixOp (A.Accelerate n) = QVarOp $ Qual (ModuleName "Acc") $ name n
infixOp (A.Primitive n)  = QVarOp $ UnQual $ name n

acc    = TyApp $ TyCon $ qualAcc $ Ident "Acc"
exp    = TyApp $ TyCon $ qualAcc $ Ident "Exp"
scalar = TyApp $ TyCon $ qualAcc $ Ident "Scalar"
vector = TyApp $ TyCon $ qualAcc $ Ident "Vector"
array d = TyApp (TyApp (TyCon $ qualAcc $ Ident "Array") d)
dim n  = TyCon $ qualAcc $ Ident $ "DIM" ++ show n
int    = TyCon $ qualPrelude $ Ident "Int"
double = TyCon $ qualPrelude $ Ident "Double"

accVar :: String -> Exp
accVar name = Var $ qualAcc $ Ident name

snocList :: (Integral a) => [a] -> Exp
snocList ns =
  foldl (\e e' -> InfixApp e (QVarOp $ qualAcc $ Symbol ":.") e')
        (Var $ qualAcc $ Ident "Z")
        (map (\n -> Lit $ Int $ toInteger n) ns)

outputProgram :: A.Program -> Module
outputProgram p =
  Module noLoc (ModuleName "Main") [] Nothing Nothing imports [progSig, prog, main]
  where imports =
          [ ImportDecl { importLoc       = noLoc
                       , importModule    = ModuleName "Prelude"
                       , importQualified = True
                       , importSrc       = False
                       , importPkg       = Nothing
                       , importAs        = Just $ ModuleName "P"
                       , importSpecs     = Nothing }
          , ImportDecl { importLoc       = noLoc
                       , importModule    = ModuleName "Prelude"
                       , importQualified = False
                       , importSrc       = False
                       , importPkg       = Nothing
                       , importAs        = Nothing
                       , importSpecs     = Just (False, map (IAbs . Symbol) ["+", "-", "*", "/"]) }
          , ImportDecl { importLoc       = noLoc
                       , importModule    = ModuleName "Data.Array.Accelerate"
                       , importQualified = True
                       , importSrc       = False
                       , importPkg       = Nothing
                       , importAs        = Just $ ModuleName "Acc"
                       , importSpecs     = Nothing }
          , ImportDecl { importLoc       = noLoc
                       , importModule    = ModuleName "Data.Array.Accelerate.Interpreter"
                       , importQualified = True
                       , importSrc       = False
                       , importPkg       = Nothing
                       , importAs        = Just $ ModuleName "Backend"
                       , importSpecs     = Nothing }
          , ImportDecl { importLoc       = noLoc
                       , importModule    = ModuleName "Tail.Primitives"
                       , importQualified = False
                       , importSrc       = False
                       , importPkg       = Nothing
                       , importAs        = Nothing
                       , importSpecs     = Nothing }
          ]
        -- Assume result is always scalar double for now
        progSig = TypeSig noLoc [Ident "program"] $ acc (scalar double)
        prog = FunBind $
          [Match noLoc (Ident "program") [] Nothing
                 (UnGuardedRhs $ outputExp p) (BDecls [])]
        main = FunBind $
          [Match noLoc (Ident "main") [] Nothing
                 (UnGuardedRhs $ mainBody) (BDecls [])]
        mainBody = App (Var $ qualPrelude $ Ident "print") $
          App (Var $ Qual (ModuleName "Backend") $ Ident "run") (Var $ UnQual $ Ident "program")

outputExp :: A.Exp -> Exp
outputExp (A.Var n) = Var $ qname n 
outputExp (A.I i) = Lit $ Int i
outputExp (A.D d) = Lit $ Frac $ toRational d
outputExp (A.Shape is) = snocList is
outputExp (A.TypSig e t) = ExpTypeSig noLoc (outputExp e) (outputType t)
outputExp (A.Neg e) = NegApp $ outputExp e
outputExp (A.List es) = List $ map outputExp es
outputExp (A.InfixApp n [e]) = outputExp e
outputExp (A.InfixApp n (e1:e2:es)) =
  foldl op (op (outputExp e1) (outputExp e2)) (map outputExp es)
  where op = flip InfixApp (infixOp n)
outputExp (A.InfixApp n []) = error "invalid infix application"
outputExp (A.App n es) = foldl App (Var $ qname n) (map outputExp es)
outputExp (A.Let ident typ e1 e2) =
  let e1' = ExpTypeSig noLoc (outputExp e1) (outputType typ) in
  Let (BDecls [ PatBind noLoc (PVar $ Ident ident) Nothing
                        (UnGuardedRhs $ e1') (BDecls []) ])
      (outputExp e2)
outputExp (A.Fn ident _ e) =
  Lambda noLoc [PVar $ Ident ident] (outputExp e)

outputType :: A.Type -> Type
outputType (A.Exp btyp) = exp (outputBType btyp)
outputType (A.Acc r btyp) = acc $ array (dim r) (outputBType btyp)

outputBType :: A.BType -> Type
outputBType A.IntT = int
outputBType A.DoubleT = double