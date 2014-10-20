module Tail.Ast where

type Ident = String

data Rank
  = R Integer
  -- | Rv String          Unsupported
  -- | Radd Rank Rank     Unsupported
  deriving (Show)

data BType = IntT | DoubleT
           -- | Btyv Ident     Unsupported
  deriving (Show)

data Type
  = ArrT BType Rank
  | ShT Rank
  | SiT Rank
  | ViT Rank
  | FunT Type Type
  deriving (Show)

scalar :: BType -> Type
scalar b = ArrT b (R 0)

int = scalar IntT
double = scalar DoubleT


data Shape = Sh [Integer]
  deriving (Show)

data Exp
  = Var Ident
  | I Integer
  | D Double
  | Inf
  | Neg Exp
  | Let Ident Type Exp Exp
  | Op String [Exp]
  | Fn Ident Type Exp
  | Vc [Exp]
  deriving (Show)

type Program = Exp
