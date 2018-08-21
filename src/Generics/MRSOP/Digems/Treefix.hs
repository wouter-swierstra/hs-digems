{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
module Generics.MRSOP.Digems.Treefix where

import Data.Proxy
import Data.Functor.Const

import Control.Monad.Identity

import Data.Text.Prettyprint.Doc

import Generics.MRSOP.Util
import Generics.MRSOP.Base
import Generics.MRSOP.Digems.Renderer

-- |An untyped tree prefix, 'UTx' is basically an n-hole context. The untyped
--  refers to the lack of an index that maintains the type of
--  the holes. This is an issue with Haskell in general. The Agda equivalent
--  keeps such index.
data UTx :: (kon -> *) -> [[[Atom kon]]] -> Nat -> (Nat -> *) -> *  where
  UTxHere :: (IsNat i) => x i -> UTx ki codes i x
  UTxPeel :: (IsNat n) => Constr (Lkup i codes) n
          -> UTxNP ki codes (Lkup n (Lkup i codes)) x
          -> UTx ki codes i x

-- |Returns the index of the UTx as a singleton.
getUTxSNat :: (IsNat ix) => UTx ki codes ix f -> SNat ix
getUTxSNat _ = getSNat (Proxy :: Proxy ix)


-- |A version of 'UTx' for products.
data UTxNP :: (kon -> *) -> [[[Atom kon]]] -> [Atom kon] -> (Nat -> *) -> *
    where
  UTxNPNil   :: UTxNP ki codes '[] x
  UTxNPPath  :: (IsNat i)
            => UTx ki codes i x
            -> UTxNP ki codes prod x
            -> UTxNP ki codes (I i ': prod) x
  UTxNPSolid :: ki k
            -> UTxNP ki codes prod x
            -> UTxNP ki codes (K k ': prod) x

-- |Our 'UTx' is a higher order functor and can be mapped over.
utxMap :: (Monad m)
       => (forall i . IsNat i => f i -> m (g i))
       -> UTx ki codes i f 
       -> m (UTx ki codes i g)
utxMap f (UTxHere x)       = UTxHere   <$> f x
utxMap f (UTxPeel c utxnp) = UTxPeel c <$> utxnpMap f utxnp

utxMapI :: (forall i . IsNat i => f i -> g i)
        -> UTx ki codes i f
        -> UTx ki codes i g
utxMapI f = runIdentity . utxMap (return . f)

-- |Analogous to 'utxMap'
utxnpMap :: (Monad m)
         => (forall i . IsNat i => f i -> m (g i))
         -> UTxNP ki codes prod f 
         -> m (UTxNP ki codes prod g)
utxnpMap f UTxNPNil = return UTxNPNil
utxnpMap f (UTxNPPath utx rest) = UTxNPPath <$> utxMap f utx <*> utxnpMap f rest
utxnpMap f (UTxNPSolid ki rest) = UTxNPSolid ki <$> utxnpMap f rest

-- |Similar to 'utxMap', but allows to refine the structure of
--  a treefix if need be
utxRefine :: (Monad m)
       => (forall i . IsNat i => f i -> m (UTx ki codes i g))
       -> UTx ki codes i f 
       -> m (UTx ki codes i g)
utxRefine f (UTxHere x)       = f x
utxRefine f (UTxPeel c utxnp) = UTxPeel c <$> utxnpRefine f utxnp

-- |Analogous to 'utxRefine'
utxnpRefine :: (Monad m)
         => (forall i . IsNat i => f i -> m (UTx ki codes i g))
         -> UTxNP ki codes prod f 
         -> m (UTxNP ki codes prod g)
utxnpRefine f UTxNPNil = return UTxNPNil
utxnpRefine f (UTxNPPath utx rest) = UTxNPPath <$> utxRefine f utx
                                               <*> utxnpRefine f rest
utxnpRefine f (UTxNPSolid ki rest) = UTxNPSolid ki <$> utxnpRefine f rest

-- |A stiff treefix is one with no holes
utxStiff :: Fix ki codes v -> UTx ki codes v f
utxStiff (Fix x) = case sop x of
  Tag c p -> UTxPeel c (utxnpStiff p)

-- |Analogous to 'utxSolid'
utxnpStiff :: PoA ki (Fix ki codes) prod -> UTxNP ki codes prod f
utxnpStiff NP0            = UTxNPNil
utxnpStiff (NA_K k :* as) = UTxNPSolid k           (utxnpStiff as)
utxnpStiff (NA_I x :* as) = UTxNPPath (utxStiff x) (utxnpStiff as)

instance (Show1 ki , Show1 x) => Show (UTx ki codes i x) where
  show (UTxHere x) = "[" ++ show1 x ++ "]"
  show (UTxPeel c rest) = "(" ++ show c ++ "| " ++ show rest ++ ")"

instance (Show1 ki , Show1 x) => Show (UTxNP ki codes prod x) where
  show UTxNPNil = "Nil"
  show (UTxNPPath p ps) = show p ++ " :* " ++ show ps
  show (UTxNPSolid ki ps) = show1 ki ++ " :* " ++ show ps

-- * Pretty Printing

utxPretty :: forall ki fam codes x i ann
           . (Show1 ki , Show1 x , Renderer ki fam codes , IsNat i)
          => Proxy fam
          -> UTx ki codes i x
          -> Doc ann
utxPretty pfam (UTxHere x)
  = braces (brackets $ pretty $ show1 x)
utxPretty pfam utx@(UTxPeel c rest)
  = renderI pfam (getUTxSNat utx) (Tag c $ utxnpPretty rest)
  where
    utxnpPretty :: UTxNP ki codes prod x
                -> PoA ki (Const (Doc ann)) prod
    utxnpPretty UTxNPNil = NP0
    utxnpPretty (UTxNPSolid k rest)
      = NA_K k :* utxnpPretty rest
    utxnpPretty (UTxNPPath i rest)
      = NA_I (Const $ utxPretty pfam i) :* utxnpPretty rest
     