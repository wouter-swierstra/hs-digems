{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE GADTs #-}
module Data.Digems.Example where

import qualified Data.Map as M
import qualified Data.Set as S
import Data.Functor.Const
import Data.Text.Prettyprint.Doc

import Generics.MRSOP.Util
import Generics.MRSOP.Base
import Generics.MRSOP.Opaque
import Generics.MRSOP.TH

import Generics.MRSOP.Digems.Digest
import Generics.MRSOP.Digems.Treefix
import Data.Digems.Patch
import Data.Digems.Patch.Diff
import Data.Digems.MetaVar
import Data.Digems.Change

instance Digestible1 Singl where
  digest1 (SString s) = hashStr s
  digest1 (SInt s)    = hashStr (show s)
  digest1 _           = error "No one told me!"

-- |2-3-Trees declaration
data Tree23
  = Node2 Int Tree23 Tree23
  | Node3 Int Tree23 Tree23 Tree23
  | Leaf
  deriving (Eq , Show)

deriveFamily [t| Tree23 |]
{-
instance Renderer Singl FamTree23 CodesTree23 where
  renderK _ (SString s) = pretty s
  renderK _ (SInt i)    = pretty i

  renderI _ IdxTree23 Leaf_ = pretty "leaf"
  renderI _ IdxTree23 (Node2_ i dl dr)
    = tupled [pretty "Node2" <+> getConst dr <+> getConst dr]
  renderI _ IdxTree23 (Node3_ i dl dm dr)
    = tupled [pretty "Node3" <+> getConst dl <+> getConst dm <+> getConst dr]
-}

mt1 , mt2 , mt3 , mt4 :: Tree23
mt1 = Node2 10 Leaf Leaf
mt2 = Node3 20 Leaf mt1 Leaf
mt3 = Node2 30 Leaf Leaf
mt4 = Node3 50 mt1 mt2 mt3

big1 , big2 , big3 :: Tree23
big1 = Node3 100
        (Node2 200 mt4 mt3)
        (Node2 100 Leaf mt1)
        (Node3 300 Leaf mt4 Leaf)
big3 = Node3 100
        (Node2 200 mt4 mt3)
        (Node2 100 Leaf mt1)
        (Node3 300 Leaf Leaf Leaf)

big2 = Node2 100
        (Node2 800 mt4 mt3)
        (Node2 200 mt4 (Node3 300 mt1 mt3 Leaf))

tr :: Tree23 -> Fix Singl CodesTree23 'Z
tr = dfrom . into

dgms :: Tree23 -> Tree23 -> Patch Singl CodesTree23 'Z
dgms x y = diff 1 (dfrom $ into x) (dfrom $ into y)

o , p , q :: Tree23
o = Node2 10 (Node3 100 Leaf Leaf Leaf) (Node2 1000 Leaf Leaf)
p = Node2 20 (Node3 100 (Node2 50 Leaf Leaf) Leaf Leaf) (Node2 1000 Leaf Leaf)
q = Node2 10 (Node3 100 Leaf Leaf Leaf) (Node3 200 Leaf Leaf (Node2 1000 Leaf Leaf))
{-
import Generics.MRSOP.Examples.SimpTH




type MyFix = Fix Singl CodesStmtString

tr :: Decl String -> MyFix (S (S Z))
tr = dfrom . into @FamStmtString

genFib :: MyFix (S (S Z))
genFib = tr $ test1 "fib" "n" "aux"

genFib2 :: MyFix (S (S Z))
genFib2 = tr $ test1 "fab" "m" "b"
-}

type TreeTerm = UTx Singl CodesTree23 (MetaVarIK Singl) (I Z)

unif1 :: TreeTerm
unif1 = UTxPeel CZ (UTxOpq (SInt 100)
                 :* UTxHole (NA_I $ Const 1)
                 :* UTxHole (NA_I $ Const 2)
                 :* NP0)
unif12 :: TreeTerm
unif12 = UTxPeel CZ (UTxOpq (SInt 500)
                 :* UTxHole (NA_I $ Const 1)
                 :* UTxHole (NA_I $ Const 2)
                 :* NP0)

unif2 :: TreeTerm
unif2 = UTxPeel CZ (UTxOpq (SInt 200)
                 :* UTxHole (NA_I $ Const 4)
                 :* UTxHole (NA_I $ Const 5)
                 :* NP0)
unif22 :: TreeTerm
unif22 = UTxPeel CZ (UTxOpq (SInt 500)
                 :* UTxHole (NA_I $ Const 4)
                 :* UTxHole (NA_I $ Const 5)
                 :* NP0)



change1 = CMatch S.empty unif1 unif12
change2 = CMatch S.empty unif2 unif22

{-
unif2 :: TreeTerm
unif2 = UTxPeel CZ (UTxOpq (SInt 100)
                 :* UTxPeel (CS CZ)
                    (UTxHole (NA_K $ Annotate 6 (SInt 42))
                     :* UTxHole (NA_I $ Const 2)
                     :* UTxPeel (CS (CS CZ)) NP0
                     :* UTxPeel (CS (CS CZ)) NP0
                     :* NP0)
                 :* UTxPeel (CS (CS CZ)) NP0
                 :* NP0)
-}
